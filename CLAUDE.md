# CLAUDE.md — tourism-leads / JSR BPO Intelligence Platform

## Was die Anwendung macht
Ursprünglich DACH Tourismus-Lead-Management für Call-Center (siehe `README.md`),
inzwischen zu einer breiteren **BPO Intelligence Platform** gewachsen. Mehrere
Geschäftsmodule (HR, Mitarbeiter, Client, Buchhaltung, Belege, Stempel, Leads)
liegen als monolithische HTML-Dateien im `frontend/`-Ordner.

## Modul-Scope (wichtig)
- **Kernmodule** (Fokus, hier wird weiterentwickelt):
  - `frontend/hr.html`
  - `frontend/mitarbeiter.html`
  - `frontend/client.html`
- **Ausgekapselt / nicht weiterentwickeln** (separates Kleinprojekt, wird später
  aus dem Repo gezogen):
  - `frontend/belege.html`
  - `beleg_server.py` (Root, lokaler HTTP-Server auf Port 4001)
- **Nachrangig**: `leads.html`, `buchhaltung.html`, `stempel.html`,
  Nebenseiten (`bewerber.html`, `index.html`, `payslip_preview.html`,
  `setup.html`, `showcase.html`, `dummy_loader.html`).

**Hintergrund:** Vom User am 2026-05-26 explizit als langfristiger Scope
festgelegt. Die `README.md` beschreibt nur den ursprünglichen
Tourism-Leads-Teil und spiegelt diese Priorisierung nicht wider — bei
Konflikten gilt CLAUDE.md.

**Verhaltensregeln:**
- Bei vagen oder mehrdeutigen Anfragen kurz nachfragen, statt stillschweigend
  ein Modul anzunehmen. Nur wenn die Anfrage einen eindeutigen inhaltlichen
  Hinweis enthält (z. B. „Bewerber", „Schicht", „Kunde"), ohne Rückfrage
  darauf basieren.
- Keine proaktiven Refactorings, Cleanups oder Feature-Vorschläge für
  `belege.html` / `beleg_server.py`. Nur reagieren, wenn ausdrücklich danach
  gefragt wird, und dann darauf hinweisen, dass das Modul ohnehin ausgekapselt
  wird.
- Bei nachrangigen Modulen vorsichtiger mit umfangreichen Änderungen sein;
  im Zweifel vorher klären, ob sich der Aufwand lohnt.
- Architektur- und übergreifende Vorschläge primär an `hr.html`,
  `mitarbeiter.html`, `client.html` ausrichten — nicht an Modulen, die
  ausgekapselt oder nachrangig sind.

### Belege-Auskapselung — offene technische Schuld
`hr.html` enthält einen eingebetteten Belege-/Buchhaltungs-Bereich
(ca. Zeilen 17500–19000), der direkt `http://localhost:4001/{scan,file,save}`
des `beleg_server.py` aufruft und die `COMPANIES`-Liste (Parklane 1–4) mit
`beleg_server.py:24` dupliziert.

**Bevor `belege.html` + `beleg_server.py` aus dem Repo ausgekapselt werden
können**, muss dieser Block in `hr.html` entweder mitmigriert oder vollständig
vom Port-4001-Aufruf entkoppelt werden.

**Arbeitsregel: nicht nebenbei anfassen.** Diese Migration ist ein dediziertes
Vorhaben. Bei laufenden Arbeiten an `hr.html` den Belege-Block in Ruhe lassen
— keine Refactorings, kein „mal eben aufräumen", keine Drive-by-Änderungen an
den Port-4001-Aufrufen oder der duplizierten `COMPANIES`-Konstante. Wenn eine
andere Aufgabe den Block berührt, vorher mit dem User klären.

## Technologie-Stack

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
- `beleg_server.py` ist ein eigenständiger Python-HTTP-Server (Port 4001).

## Deployment
- **Frontend**: wird via **Vercel** direkt aus dem GitHub-Repo deployt
  (siehe `.vercel/`). Push auf den Tracking-Branch löst Deploy aus.
- **Backend**: läuft **separat** (nicht auf Vercel). Eigene Infrastruktur,
  unabhängiger Lifecycle.

Konsequenz: Jeder Push auf den deploy-Branch ist produktionswirksam für das
Frontend. Entsprechend vorsichtig vorgehen.

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
├── beleg_server.py              Lokaler Beleg-Server (Port 4001, wird ausgekapselt)
└── README.md                    beschreibt nur den ursprünglichen Tourism-Leads-Teil
```

## Arbeitsregeln

### Git / Push
- **Vor jedem `git push` immer `git diff` (bzw. `git diff origin/<branch>...HEAD`
  für bereits committete Änderungen) zeigen und auf ausdrückliche Bestätigung
  des Users warten.** Erst nach „ok"/„push" tatsächlich pushen.
- Commits werden nur auf explizite Aufforderung erstellt.

### Secrets
- **Niemals `.env`-Dateien oder Secrets committen**
  (`backend/.env`, API-Keys: `APOLLO_API_KEY`, `HUNTER_API_KEY`,
  `PROXYCURL_API_KEY`, `ANTHROPIC_API_KEY`, `SECRET_KEY`,
  Datenbank-Passwörter, Vercel-Tokens).
- Beim Staging gezielt Dateien benennen, nicht `git add -A` / `git add .`
  verwenden.
- Falls eine `.env.example` benötigt wird, nur Platzhalter, keine echten Werte.
