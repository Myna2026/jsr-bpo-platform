-- ============================================================
-- TOURISM LEADS PLATFORM — PostgreSQL Schema
-- ============================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";   -- für Fuzzy-Search
CREATE EXTENSION IF NOT EXISTS "unaccent";  -- für DE/AT/CH Namen

-- ============================================================
-- ENUM TYPES
-- ============================================================

CREATE TYPE company_category AS ENUM (
  'airline',
  'kreuzfahrt',
  'veranstalter',
  'pauschalreise',
  'ota',             -- Online Travel Agency
  'vermittler',      -- Reisebüro / Vermittler
  'hotelkette',
  'boutique_hotel',
  'mietwagen',
  'dmc',             -- Destination Management Company
  'incoming',
  'transfer',
  'bahn',
  'bus_coach',
  'activity_provider',
  'tech_provider',   -- Travel Tech, GDS
  'versicherung',
  'sonstiges'
);

CREATE TYPE company_size AS ENUM (
  'micro',       -- < 10 MA
  'small',       -- 10–49
  'medium',      -- 50–249
  'large',       -- 250–999
  'enterprise'   -- 1000+
);

CREATE TYPE country_code AS ENUM ('DE', 'AT', 'CH');

CREATE TYPE lead_priority AS ENUM ('low', 'medium', 'high', 'vip');

CREATE TYPE lead_status AS ENUM (
  'neu',
  'in_bearbeitung',
  'kontaktiert',
  'qualifiziert',
  'angebot',
  'gewonnen',
  'verloren',
  'do_not_contact'
);

CREATE TYPE contact_department AS ENUM (
  'geschaeftsfuehrung',
  'management',
  'sales',
  'marketing',
  'operations',
  'customer_service',
  'finance',
  'hr',
  'it',
  'procurement',
  'sonstiges'
);

CREATE TYPE job_platform AS ENUM (
  'indeed',
  'stepstone',
  'monster',
  'linkedin',
  'xing_jobs',
  'arbeitsagentur',
  'glassdoor',
  'kununu',
  'jobware',
  'stellenanzeigen_de',
  'hokify',
  'karriere_at',
  'jobs_ch',
  'sonstiges'
);

CREATE TYPE activity_type AS ENUM (
  'call_ausgehend',
  'call_eingehend',
  'email_ausgehend',
  'email_eingehend',
  'linkedin_nachricht',
  'meeting',
  'notiz',
  'statuswechsel'
);

-- ============================================================
-- COMPANIES
-- ============================================================

CREATE TABLE companies (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- Basisdaten
  name                VARCHAR(255) NOT NULL,
  name_normalized     VARCHAR(255) GENERATED ALWAYS AS (lower(unaccent(name))) STORED,
  legal_form          VARCHAR(50),              -- GmbH, AG, KG, ...
  brand_names         TEXT[],                   -- Handelsmarken / DBA

  -- Kategorie & Typ
  category            company_category NOT NULL,
  subcategory         VARCHAR(100),
  tags                TEXT[],                   -- z.B. ['luxury', 'b2b', 'gruppenreisen']

  -- Geographie
  country             country_code NOT NULL,
  state               VARCHAR(100),             -- Bundesland / Kanton
  city                VARCHAR(100),
  postal_code         VARCHAR(20),
  street              VARCHAR(255),
  address_full        TEXT,                     -- formatierte Adresse

  -- Kontakt
  website             VARCHAR(500),
  email_general       VARCHAR(255),
  email_sales         VARCHAR(255),
  phone_main          VARCHAR(50),
  phone_sales         VARCHAR(50),
  linkedin_url        VARCHAR(500),
  xing_url            VARCHAR(500),

  -- Unternehmensgröße & Finanzen
  size                company_size,
  employees_approx    INTEGER,                  -- geschätzte MA-Zahl
  revenue_approx_eur  BIGINT,                   -- Jahresumsatz ca. in €
  revenue_year        SMALLINT,                 -- Berichtsjahr
  revenue_source      VARCHAR(100),             -- Bundesanzeiger, Schätzung, etc.
  founded_year        SMALLINT,
  hrb_number          VARCHAR(50),              -- Handelsregisternummer

  -- CRM
  priority            lead_priority NOT NULL DEFAULT 'medium',
  status              lead_status NOT NULL DEFAULT 'neu',
  owner_id            UUID,                     -- FK → users (später)
  score               SMALLINT DEFAULT 50 CHECK (score BETWEEN 0 AND 100),
  notes               TEXT,

  -- Signale
  has_open_jobs       BOOLEAN DEFAULT FALSE,
  open_jobs_count     INTEGER DEFAULT 0,
  last_job_signal_at  TIMESTAMPTZ,
  news_signal         TEXT,                     -- letzter relevanter News-Treffer

  -- Meta
  data_source         VARCHAR(100),             -- woher stammt der Datensatz
  data_quality        SMALLINT DEFAULT 50 CHECK (data_quality BETWEEN 0 AND 100),
  last_crawled_at     TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  is_active           BOOLEAN DEFAULT TRUE
);

-- Indizes Companies
CREATE INDEX idx_companies_category   ON companies(category);
CREATE INDEX idx_companies_country    ON companies(country);
CREATE INDEX idx_companies_status     ON companies(status);
CREATE INDEX idx_companies_priority   ON companies(priority);
CREATE INDEX idx_companies_size       ON companies(size);
CREATE INDEX idx_companies_score      ON companies(score DESC);
CREATE INDEX idx_companies_name_trgm  ON companies USING GIN (name_normalized gin_trgm_ops);
CREATE INDEX idx_companies_tags       ON companies USING GIN (tags);
CREATE INDEX idx_companies_active     ON companies(is_active) WHERE is_active = TRUE;

-- ============================================================
-- CONTACTS (Mitarbeiter / Ansprechpartner)
-- ============================================================

CREATE TABLE contacts (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id          UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,

  -- Person
  first_name          VARCHAR(100),
  last_name           VARCHAR(100) NOT NULL,
  salutation          VARCHAR(20),
  title               VARCHAR(50),
  full_name           VARCHAR(255) GENERATED ALWAYS AS (
                        COALESCE(first_name || ' ', '') || last_name
                      ) STORED,

  -- Position
  job_title           VARCHAR(255),
  department          contact_department,
  seniority           VARCHAR(50),             -- C-Level, VP, Director, Manager, ...
  is_decision_maker   BOOLEAN DEFAULT FALSE,

  -- Kontakt
  email               VARCHAR(255),
  email_verified      BOOLEAN DEFAULT FALSE,
  phone_direct        VARCHAR(50),
  phone_mobile        VARCHAR(50),
  linkedin_url        VARCHAR(500),
  xing_url            VARCHAR(500),

  -- Verifikation
  is_current_employee BOOLEAN DEFAULT TRUE,    -- aktuell noch beschäftigt?
  verified_at         TIMESTAMPTZ,
  source              VARCHAR(100),            -- linkedin, xing, manuell, ...

  -- CRM
  notes               TEXT,
  last_contacted_at   TIMESTAMPTZ,
  do_not_contact      BOOLEAN DEFAULT FALSE,

  -- Meta
  last_crawled_at     TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_contacts_company      ON contacts(company_id);
CREATE INDEX idx_contacts_department   ON contacts(department);
CREATE INDEX idx_contacts_decision     ON contacts(is_decision_maker) WHERE is_decision_maker = TRUE;
CREATE INDEX idx_contacts_current      ON contacts(is_current_employee) WHERE is_current_employee = TRUE;
CREATE INDEX idx_contacts_email        ON contacts(email) WHERE email IS NOT NULL;

-- ============================================================
-- JOB POSTINGS (Stellenausschreibungen als Kauf-Signale)
-- ============================================================

CREATE TABLE job_postings (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id          UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,

  -- Job-Daten
  title               VARCHAR(500) NOT NULL,
  department          VARCHAR(200),
  location            VARCHAR(200),
  job_type            VARCHAR(50),             -- Vollzeit, Teilzeit, etc.
  remote_ok           BOOLEAN,

  -- Plattform
  platform            job_platform NOT NULL,
  external_url        VARCHAR(1000),
  external_id         VARCHAR(200),            -- ID auf der Plattform
  platform_posted_at  DATE,

  -- Analyse
  is_growth_signal    BOOLEAN DEFAULT FALSE,   -- deutet auf Wachstum hin?
  signal_category     VARCHAR(100),            -- 'expansion', 'new_dept', 'replacement'
  relevance_score     SMALLINT DEFAULT 50,

  -- Meta
  is_active           BOOLEAN DEFAULT TRUE,
  first_seen_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  closed_at           TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_jobs_company        ON job_postings(company_id);
CREATE INDEX idx_jobs_platform       ON job_postings(platform);
CREATE INDEX idx_jobs_active         ON job_postings(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_jobs_signal         ON job_postings(is_growth_signal) WHERE is_growth_signal = TRUE;
CREATE INDEX idx_jobs_posted         ON job_postings(platform_posted_at DESC);

-- ============================================================
-- CRM ACTIVITIES (Anruf-Protokoll / Call Center)
-- ============================================================

CREATE TABLE crm_activities (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id          UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  contact_id          UUID REFERENCES contacts(id) ON DELETE SET NULL,

  type                activity_type NOT NULL,
  subject             VARCHAR(500),
  body                TEXT,
  outcome             VARCHAR(100),            -- 'kein_anschluss', 'voicemail', 'termin', etc.
  duration_seconds    INTEGER,

  -- Wer hat die Aktivität gemacht
  agent_name          VARCHAR(100),
  agent_id            UUID,                    -- FK → users später

  -- Follow-up
  next_action         VARCHAR(500),
  next_action_due_at  TIMESTAMPTZ,

  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_activities_company   ON crm_activities(company_id);
CREATE INDEX idx_activities_contact   ON crm_activities(contact_id);
CREATE INDEX idx_activities_type      ON crm_activities(type);
CREATE INDEX idx_activities_agent     ON crm_activities(agent_id);
CREATE INDEX idx_activities_due       ON crm_activities(next_action_due_at) WHERE next_action_due_at IS NOT NULL;

-- ============================================================
-- CRAWLER RUNS (Audit-Log für alle Crawl-Jobs)
-- ============================================================

CREATE TABLE crawler_runs (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  crawler_name        VARCHAR(100) NOT NULL,   -- 'bundesanzeiger', 'linkedin', 'indeed', ...
  status              VARCHAR(20) NOT NULL,    -- 'running', 'success', 'failed', 'partial'
  records_found       INTEGER DEFAULT 0,
  records_new         INTEGER DEFAULT 0,
  records_updated     INTEGER DEFAULT 0,
  error_message       TEXT,
  started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finished_at         TIMESTAMPTZ,
  meta                JSONB                    -- crawler-spezifische Zusatzinfos
);

CREATE INDEX idx_crawler_name   ON crawler_runs(crawler_name);
CREATE INDEX idx_crawler_status ON crawler_runs(status);
CREATE INDEX idx_crawler_time   ON crawler_runs(started_at DESC);

-- ============================================================
-- UPDATED_AT TRIGGER (auto-update)
-- ============================================================

CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at_companies
  BEFORE UPDATE ON companies
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_contacts
  BEFORE UPDATE ON contacts
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- ============================================================
-- VIEWS für das Frontend
-- ============================================================

-- Lead Grid View (Hauptansicht)
CREATE VIEW v_lead_grid AS
SELECT
  c.id,
  c.name,
  c.category,
  c.subcategory,
  c.country,
  c.city,
  c.size,
  c.employees_approx,
  c.revenue_approx_eur,
  c.priority,
  c.status,
  c.score,
  c.website,
  c.email_general,
  c.phone_main,
  c.has_open_jobs,
  c.open_jobs_count,
  c.last_job_signal_at,
  c.notes,
  c.owner_id,
  -- Kontakte aggregiert
  COUNT(DISTINCT ct.id) FILTER (WHERE ct.is_current_employee)  AS contacts_total,
  COUNT(DISTINCT ct.id) FILTER (WHERE ct.is_decision_maker)    AS decision_makers_total,
  -- Letzte Aktivität
  MAX(a.created_at)                                             AS last_activity_at,
  COUNT(DISTINCT a.id)                                          AS activities_total,
  c.updated_at,
  c.created_at
FROM companies c
LEFT JOIN contacts ct ON ct.company_id = c.id
LEFT JOIN crm_activities a ON a.company_id = c.id
WHERE c.is_active = TRUE
GROUP BY c.id;

-- ============================================================
-- SEED: Kategorien-Referenz
-- ============================================================

COMMENT ON COLUMN companies.category IS
  'airline=Fluggesellschaft, kreuzfahrt=Reederei, veranstalter=Reiseveranstalter, 
   pauschalreise=Pauschalreiseanbieter, ota=Online Reiseportal, vermittler=Reisebüro,
   hotelkette=Hotelgruppe, boutique_hotel=Einzelhotel, mietwagen=Autovermietung,
   dmc=Incoming Agentur, transfer=Transfer/Shuttle, bahn=Bahnunternehmen,
   bus_coach=Busreisen, activity_provider=Aktivitäten/Erlebnisse,
   tech_provider=Travel-Tech/GDS, versicherung=Reiseversicherung';
