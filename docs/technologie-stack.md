# Technologie-Stack und Ordnerstruktur

> Ausgelagert aus `CLAUDE.md` (Stand 2026-09-15). Beschreibt vor allem den
> ursprünglichen Tourism-Leads-Backend-Teil; die Portale laufen heute über
> Supabase (siehe `ARCHITEKTUR.md`).

### Backend (`backend/`)
- **FastAPI 0.115** + Uvicorn — REST API unter `/api/v1`
- **SQLAlchemy 2 (async)** + **asyncpg** + **Alembic** — PostgreSQL 16
- **Pydantic v2** für Settings/Validation
- **Celery 5.4 + Redis 7** — Hintergrund-Tasks, Beat-Scheduler
  (täglich Job-Scan 07:00, wöchentlich Enrichment So 02:00)
- **Playwright (chromium)** für Headless-Crawling
- **httpx + BeautifulSoup + lxml** für klassisches Scraping
- **openpyxl** für Excel-Export
- **Anthropic SDK 0.40** für KI-Scoring (optional)

### Frontend (`frontend/`)
- **Keine Build-Pipeline**: Trotz `src/`-Ordner (weitgehend leer) sind die
  HTML-Dateien standalone und laden React 18, Babel-Standalone und xlsx
  zur Laufzeit über **unpkg-CDN**.
- `src/lib/api.js` existiert als Vite-Client (`import.meta.env.VITE_API_URL`),
  wird von den HTML-Modulen praktisch nicht genutzt.

### Infrastruktur
- `docker/docker-compose.yml` startet **nur** `postgres` + `redis`.
  Die im README erwähnten `api`/`worker`/`beat`-Services sind dort nicht
  definiert.

## Ordnerstruktur
```
tourism-leads/
├── backend/
│   ├── app/
│   │   ├── main.py              FastAPI Entry (6 Router)
│   │   ├── core/config.py       Pydantic Settings
│   │   ├── api/routes/          companies, contacts, jobs, activities, crawler, export
│   │   ├── models/models.py     ORM: Company, Contact, JobPosting, CrmActivity, CrawlerRun
│   │   ├── crawler/             company_crawler, job_signal_monitor, apollo_*, career_*, rfp_*, playwright_*
│   │   ├── tasks/celery_app.py  Celery + Beat-Schedules
│   │   └── db/session.py
│   ├── schema.sql + hr_schema.sql
│   └── requirements.txt
├── frontend/                    Standalone HTML-Module (React via CDN)
│   ├── hr.html / mitarbeiter.html / client.html   ← Kern
│   └── src/                     (weitgehend leerer Vite-Stub)
├── docker/docker-compose.yml    postgres + redis
└── README.md                    beschreibt nur den ursprünglichen Tourism-Leads-Teil
```
