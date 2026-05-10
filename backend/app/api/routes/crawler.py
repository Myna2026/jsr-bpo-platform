"""Crawler Admin Route"""
from uuid import UUID
from fastapi import APIRouter, Depends, BackgroundTasks
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from datetime import datetime

from app.db.session import get_db
from app.models.models import Company, CrawlerRun

router = APIRouter()

@router.post("/seed-import")
async def trigger_seed_import(background_tasks: BackgroundTasks, db: AsyncSession = Depends(get_db)):
    """Importiert DACH-Tourism Seed-Unternehmen (einmalig)"""
    from app.crawler.company_crawler import company_crawler
    background_tasks.add_task(company_crawler.import_seed_data, db)
    return {"status": "gestartet", "message": "Seed-Import läuft im Hintergrund"}

@router.post("/job-scan")
async def trigger_job_scan(background_tasks: BackgroundTasks, db: AsyncSession = Depends(get_db)):
    """Startet manuell einen Job-Board Scan"""
    from app.crawler.job_signal_monitor import job_monitor
    background_tasks.add_task(job_monitor.run_full_scan, db)
    return {"status": "gestartet", "message": "Job-Scan läuft im Hintergrund"}

@router.post("/enrich/{company_id}")
async def enrich_company(company_id: UUID, background_tasks: BackgroundTasks, db: AsyncSession = Depends(get_db)):
    """Reichert ein einzelnes Unternehmen an"""
    company = await db.get(Company, company_id)
    if not company:
        from fastapi import HTTPException
        raise HTTPException(404, "Unternehmen nicht gefunden")
    from app.crawler.job_signal_monitor import job_monitor
    background_tasks.add_task(job_monitor.run_for_company, db, company)
    return {"status": "gestartet", "company": company.name}

@router.get("/runs")
async def get_crawler_runs(limit: int = 20, db: AsyncSession = Depends(get_db)):
    """Letzte Crawler-Ausführungen"""
    runs = (await db.execute(
        select(CrawlerRun).order_by(CrawlerRun.started_at.desc()).limit(limit)
    )).scalars().all()
    return runs


@router.post("/extended-seed-import")
async def trigger_extended_seed(background_tasks: BackgroundTasks, db: AsyncSession = Depends(get_db)):
    """Importiert ~200 weitere DACH-Tourism Unternehmen"""
    from app.crawler.company_crawler import import_extended_seed
    background_tasks.add_task(import_extended_seed, db)
    return {"status": "gestartet", "message": "Erweiterter Import läuft — ~200 weitere Firmen werden geladen"}


@router.post("/enrich-people")
async def trigger_people_enrichment(background_tasks: BackgroundTasks, db: AsyncSession = Depends(get_db)):
    """Startet Apollo.io People Import für alle Firmen"""
    from app.crawler.apollo_import import run_people_import
    background_tasks.add_task(run_people_import, db)
    return {"status": "gestartet", "message": "Apollo People Import läuft — 2-5 Mitarbeiter pro Firma werden geladen"}


@router.post("/enrich-people-test")
async def test_people_enrichment(db: AsyncSession = Depends(get_db)):
    """Testet Apollo für eine einzelne Firma — zeigt sofort Ergebnis"""
    from app.crawler.apollo_import import fetch_people_for_company
    from app.models.models import Company
    from sqlalchemy import select
    import httpx

    company = (await db.execute(
        select(Company).where(Company.is_active == True).limit(1)
    )).scalar_one_or_none()

    if not company:
        return {"error": "Keine Firma gefunden"}

    try:
        async with httpx.AsyncClient() as client:
            people = await fetch_people_for_company(client, company, max_people=3)
        return {
            "company": company.name,
            "people_found": len(people),
            "people": people,
        }
    except Exception as e:
        return {"error": str(e), "company": company.name}


@router.post("/rfp-scan")
async def trigger_rfp_scan(background_tasks: BackgroundTasks, db: AsyncSession = Depends(get_db)):
    """Scannt TED, Vergabeportale und News nach Call Center Ausschreibungen"""
    from app.crawler.rfp_crawler import rfp_orchestrator
    background_tasks.add_task(rfp_orchestrator.run_scan, db)
    return {"status": "gestartet", "message": "RFP-Scan läuft — sucht nach Call Center Ausschreibungen in DACH"}


@router.get("/rfp-results")
async def get_rfp_results(limit: int = 50, db: AsyncSession = Depends(get_db)):
    """Zeigt die letzten gefundenen Ausschreibungen"""
    from app.crawler.rfp_crawler import rfp_orchestrator
    rfps = await rfp_orchestrator.store.get_latest_rfps(db, limit=limit)
    return {"total": len(rfps), "rfps": rfps}


@router.post("/enrich-contacts")
async def trigger_contact_enrichment(background_tasks: BackgroundTasks, db: AsyncSession = Depends(get_db)):
    """Reichert Kontakte mit vollen Daten an (Name, E-Mail, Telefon, LinkedIn)"""
    from app.crawler.apollo_enrichment import run_contact_enrichment
    background_tasks.add_task(run_contact_enrichment, db)
    return {"status": "gestartet", "message": "Kontakt-Enrichment läuft — holt E-Mail, Telefon, LinkedIn für alle Kontakte"}


@router.post("/career-scan")
async def trigger_career_scan(background_tasks: BackgroundTasks, db: AsyncSession = Depends(get_db)):
    """Crawlt Karriereseiten aller Firmen direkt"""
    from app.crawler.career_crawler import career_crawler
    background_tasks.add_task(career_crawler.run_full_scan, db)
    return {"status": "gestartet", "message": "Karriereseiten-Scan läuft — prüft alle 246 Firmenseiten direkt"}


@router.post("/career-scan/{company_id}")
async def trigger_career_scan_single(company_id: UUID, background_tasks: BackgroundTasks, db: AsyncSession = Depends(get_db)):
    """Crawlt Karriereseite einer einzelnen Firma"""
    from app.crawler.career_crawler import career_crawler
    company = await db.get(Company, company_id)
    if not company:
        from fastapi import HTTPException
        raise HTTPException(404, "Firma nicht gefunden")
    background_tasks.add_task(career_crawler.crawl_company, db, company)
    return {"status": "gestartet", "company": company.name}
