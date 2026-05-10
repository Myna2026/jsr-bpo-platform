"""
Celery Task Queue — Automatische Crawler-Schedules
"""
from celery import Celery
from celery.schedules import crontab
from app.core.config import settings

celery_app = Celery(
    "tourism_leads",
    broker=settings.REDIS_URL,
    backend=settings.REDIS_URL,
)

celery_app.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="Europe/Berlin",
    enable_utc=True,
    task_routes={
        "app.tasks.tasks.run_job_signal_scan": {"queue": "crawler"},
        "app.tasks.tasks.run_company_enrichment": {"queue": "crawler"},
        "app.tasks.tasks.run_seed_import": {"queue": "default"},
    },
)

# ── Schedules ────────────────────────────────────────────────
celery_app.conf.beat_schedule = {
    # Job Signals: täglich um 07:00
    "job-signal-scan-daily": {
        "task": "app.tasks.tasks.run_job_signal_scan",
        "schedule": crontab(hour=7, minute=0),
    },
    # Unternehmens-Anreicherung: wöchentlich Sonntag 02:00
    "company-enrichment-weekly": {
        "task": "app.tasks.tasks.run_company_enrichment",
        "schedule": crontab(hour=2, minute=0, day_of_week="sunday"),
    },
}


# ── Task Definitionen ────────────────────────────────────────

@celery_app.task(name="app.tasks.tasks.run_job_signal_scan", bind=True, max_retries=2)
def run_job_signal_scan(self):
    """Crawlt alle Job-Boards für alle aktiven Unternehmen"""
    import asyncio
    from app.db.session import AsyncSessionLocal
    from app.crawler.job_signal_monitor import job_monitor

    async def _run():
        async with AsyncSessionLocal() as db:
            result = await job_monitor.run_full_scan(db)
            return result

    try:
        return asyncio.run(_run())
    except Exception as exc:
        raise self.retry(exc=exc, countdown=300)


@celery_app.task(name="app.tasks.tasks.run_company_enrichment", bind=True, max_retries=1)
def run_company_enrichment(self):
    """Reichert Unternehmen mit OpenCorporates/Bundesanzeiger-Daten an"""
    import asyncio
    from app.db.session import AsyncSessionLocal
    from app.crawler.company_crawler import company_crawler

    async def _run():
        async with AsyncSessionLocal() as db:
            result = await company_crawler.enrich_with_opencorporates(db)
            return result

    try:
        return asyncio.run(_run())
    except Exception as exc:
        raise self.retry(exc=exc, countdown=600)


@celery_app.task(name="app.tasks.tasks.run_seed_import")
def run_seed_import():
    """Importiert Seed-Unternehmen — einmalig beim Setup"""
    import asyncio
    from app.db.session import AsyncSessionLocal
    from app.crawler.company_crawler import company_crawler

    async def _run():
        async with AsyncSessionLocal() as db:
            return await company_crawler.import_seed_data(db)

    return asyncio.run(_run())
