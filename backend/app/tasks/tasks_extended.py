"""
Erweiterte Celery Tasks — alle Crawler + Enrichment Services
"""
from app.tasks.celery_app import celery_app
from celery.schedules import crontab

# Erweiterte Schedules
celery_app.conf.beat_schedule.update({
    # Job Signals RSS (Indeed + BA): täglich 07:00
    "job-signal-rss-daily": {
        "task": "app.tasks.tasks_extended.run_rss_job_scan",
        "schedule": crontab(hour=7, minute=0),
    },
    # StepStone + Monster via Playwright: täglich 08:00
    "job-signal-playwright-daily": {
        "task": "app.tasks.tasks_extended.run_playwright_job_scan",
        "schedule": crontab(hour=8, minute=0),
    },
    # People Enrichment (Apollo + Hunter): wöchentlich Mo 03:00
    "people-enrichment-weekly": {
        "task": "app.tasks.tasks_extended.run_people_enrichment",
        "schedule": crontab(hour=3, minute=0, day_of_week="monday"),
    },
    # Bundesanzeiger Umsatz: monatlich 1. des Monats
    "revenue-enrichment-monthly": {
        "task": "app.tasks.tasks_extended.run_revenue_enrichment",
        "schedule": crontab(hour=2, minute=0, day_of_month="1"),
    },
})


@celery_app.task(name="app.tasks.tasks_extended.run_rss_job_scan", bind=True, max_retries=2)
def run_rss_job_scan(self):
    """Indeed RSS + Bundesagentur für alle Firmen"""
    import asyncio
    from app.db.session import AsyncSessionLocal
    from app.crawler.job_signal_monitor import job_monitor

    async def _run():
        async with AsyncSessionLocal() as db:
            return await job_monitor.run_full_scan(db)

    try:
        return asyncio.run(_run())
    except Exception as exc:
        raise self.retry(exc=exc, countdown=300)


@celery_app.task(name="app.tasks.tasks_extended.run_playwright_job_scan", bind=True, max_retries=1)
def run_playwright_job_scan(self):
    """StepStone + Monster via Playwright"""
    import asyncio
    from app.db.session import AsyncSessionLocal
    from app.crawler.playwright_crawler import playwright_crawler

    async def _run():
        async with AsyncSessionLocal() as db:
            return await playwright_crawler.run_full_scan(db)

    try:
        return asyncio.run(_run())
    except Exception as exc:
        raise self.retry(exc=exc, countdown=600)


@celery_app.task(name="app.tasks.tasks_extended.run_people_enrichment", bind=True, max_retries=1)
def run_people_enrichment(self):
    """Apollo.io + Hunter.io + Proxycurl People Enrichment"""
    import asyncio
    from app.db.session import AsyncSessionLocal
    from app.crawler.enrichment.people_enrichment import people_enrichment

    async def _run():
        async with AsyncSessionLocal() as db:
            return await people_enrichment.enrich_all_companies(db)

    try:
        return asyncio.run(_run())
    except Exception as exc:
        raise self.retry(exc=exc, countdown=600)


@celery_app.task(name="app.tasks.tasks_extended.run_revenue_enrichment", bind=True, max_retries=1)
def run_revenue_enrichment(self):
    """Bundesanzeiger Umsatz-Enrichment für DE-Firmen"""
    import asyncio
    from app.db.session import AsyncSessionLocal
    from app.crawler.enrichment.revenue_enrichment import revenue_enrichment

    async def _run():
        async with AsyncSessionLocal() as db:
            return await revenue_enrichment.enrich_all(db)

    try:
        return asyncio.run(_run())
    except Exception as exc:
        raise self.retry(exc=exc, countdown=900)


# Manuelle Trigger-Tasks für Admin-API
@celery_app.task(name="app.tasks.tasks_extended.enrich_single_company")
def enrich_single_company(company_id: str):
    """Reichert eine einzelne Firma an (alle Services)"""
    import asyncio
    from uuid import UUID
    from app.db.session import AsyncSessionLocal
    from app.models.models import Company
    from app.crawler.enrichment.people_enrichment import people_enrichment
    from app.crawler.job_signal_monitor import job_monitor

    async def _run():
        async with AsyncSessionLocal() as db:
            company = await db.get(Company, UUID(company_id))
            if not company:
                return {"error": "Firma nicht gefunden"}
            r1 = await people_enrichment.enrich_company(db, company)
            r2 = await job_monitor.run_for_company(db, company)
            return {"people": r1, "new_jobs": r2}

    return asyncio.run(_run())
