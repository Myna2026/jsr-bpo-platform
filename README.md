# Tourism Leads Platform

DACH Tourism Lead Management System für Call Center.

## Was das System kann

- **Lead Grid**: Alle DACH-Tourismusunternehmen gefiltert nach Land, Kategorie, Größe, Umsatz, Score
- **Kontakt-Profile**: Mitarbeiter je Unternehmen (via Apollo.io / Hunter.io API)
- **Job Signal Monitor**: Täglich aktualisierte Stellenausschreibungen als Kaufsignal
- **CRM Activity Log**: Anruf-Protokolle, Status-Updates, Follow-up Termine
- **Export**: CSV/Excel-Export gefiltert, direkt Excel-kompatibel

---

## Setup in 5 Schritten

### 1. Voraussetzungen
```bash
docker --version        # >= 24
docker compose version  # >= 2.20
node --version          # >= 20 (für Frontend)
python --version        # >= 3.12 (nur für lokale Entwicklung)
```

### 2. Repository klonen & konfigurieren
```bash
git clone <repo>
cd tourism-leads

# Backend .env anlegen
cp backend/.env.example backend/.env
# Öffne backend/.env und trage die API-Keys ein (siehe unten)
```

### 3. Backend starten
```bash
cd docker
docker compose up -d postgres redis
docker compose up -d api worker beat

# Seed-Daten importieren (60+ DACH-Tourismusunternehmen)
docker compose exec api python -c "
from app.tasks.celery_app import run_seed_import
run_seed_import()
"
```

### 4. Frontend starten
```bash
cd frontend
npm install
npm run dev
# Läuft auf http://localhost:3000
```

### 5. API Docs öffnen
```
http://localhost:8000/docs
```

---

## Umgebungsvariablen (backend/.env)

```env
# Pflichtfelder
DATABASE_URL=postgresql+asyncpg://leads:leads@localhost:5432/tourism_leads
REDIS_URL=redis://localhost:6379/0
SECRET_KEY=dein-geheimer-schlüssel-hier

# Optionale API-Keys für People-Enrichment
APOLLO_API_KEY=         # apollo.io — Mitarbeiter/Kontakte (empfohlen, ~$49/mo)
HUNTER_API_KEY=         # hunter.io — E-Mail-Adressen verifizieren
PROXYCURL_API_KEY=      # proxycurl.com — LinkedIn Enrichment (legal)

# KI-Scoring (optional)
ANTHROPIC_API_KEY=      # Claude API für intelligente Bewertung
```

---

## Architektur

```
tourism-leads/
├── backend/
│   ├── app/
│   │   ├── main.py              # FastAPI App
│   │   ├── core/config.py       # Settings
│   │   ├── models/models.py     # SQLAlchemy ORM
│   │   ├── api/routes/
│   │   │   ├── companies.py     # Lead CRUD + Filter
│   │   │   ├── contacts.py      # Mitarbeiter
│   │   │   ├── jobs.py          # Job Signals
│   │   │   ├── activities.py    # CRM Protokoll
│   │   │   ├── crawler.py       # Crawler-Steuerung
│   │   │   └── export.py        # CSV/Excel Export
│   │   ├── crawler/
│   │   │   ├── company_crawler.py    # Unternehmens-Crawler
│   │   │   └── job_signal_monitor.py # Job-Board Crawler
│   │   └── tasks/celery_app.py  # Hintergrund-Tasks
│   ├── schema.sql               # PostgreSQL DDL
│   └── requirements.txt
├── frontend/
│   └── src/
│       ├── components/
│       │   ├── LeadGrid.jsx     # Haupt-Tabelle
│       │   ├── Filters.jsx      # Filter-Panel
│       │   └── CompanyDetail.jsx
│       └── pages/
└── docker/
    └── docker-compose.yml
```

---

## API Endpoints (Auszug)

### Companies
| Method | Path | Beschreibung |
|--------|------|--------------|
| GET | /api/v1/companies | Lead Grid mit Filter & Paginierung |
| GET | /api/v1/companies/{id} | Firmen-Detail |
| POST | /api/v1/companies | Firma anlegen |
| PATCH | /api/v1/companies/{id} | Firma updaten |
| PATCH | /api/v1/companies/{id}/priority | Priorität setzen |
| PATCH | /api/v1/companies/{id}/status | Status setzen |

### Filter-Parameter (GET /api/v1/companies)
```
?search=tui
?category=airline&category=kreuzfahrt
?country=DE&country=AT
?size=large&size=enterprise
?priority=vip&priority=high
?status=neu
?has_open_jobs=true
?min_score=70
?min_revenue=1000000
?sort_by=score&sort_dir=desc
?page=1&page_size=50
```

### Export
```
GET /api/v1/export/companies/csv?country=DE&include_contacts=true
```

### Crawler manuell starten
```
POST /api/v1/crawler/seed-import
POST /api/v1/crawler/job-scan
POST /api/v1/crawler/enrich/{company_id}
```

---

## Nächste Schritte

### Phase 2 — People Enrichment
- [ ] Apollo.io API Integration für Mitarbeiter-Daten
- [ ] Hunter.io für E-Mail-Verifizierung
- [ ] Proxycurl für LinkedIn-Profile

### Phase 3 — Erweiterte Crawler
- [ ] StepStone via Playwright (headless)
- [ ] Bundesanzeiger Jahresabschlüsse (Umsatz)
- [ ] DTVB / DRV Mitgliederlisten
- [ ] Google Maps Business Profile

### Phase 4 — KI-Features
- [ ] Automatisches Lead-Scoring via Claude API
- [ ] Call-Vorbereitung: Gesprächs-Briefing generieren
- [ ] News-Monitoring: relevante Firmen-News täglich

### Phase 5 — Frontend Features
- [ ] Kanban-Board (Lead Pipeline)
- [ ] Tages-Aufgabenliste für Call Center Agents
- [ ] E-Mail-Vorlagen direkt aus dem Lead
- [ ] Team-Dashboard (Conversion Rates, Aktivitäten)

---

## Rechtliches

- Alle Crawler nutzen **ausschließlich öffentlich zugängliche Daten**
- `robots.txt` wird vor jedem Crawl gelesen und respektiert
- Rate-Limits eingehalten (min. 2s Delay)
- User-Agent klar als Bot deklariert
- DSGVO: Kontaktdaten nur aus offiziellen Business-Quellen (LinkedIn, Xing — Business-Kontext)
- Kein Scraping von privaten Profilen
