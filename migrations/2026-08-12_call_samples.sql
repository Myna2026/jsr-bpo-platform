-- =============================================================================
-- Call-Stichproben mit Bewertungsbogen — Schnitt 1: Gerüst (Schema + RLS)      2026-08-12
-- =============================================================================
-- HR/Management hört sich Calls einzelner Mitarbeiter an und bewertet sie anhand
-- eines Bogens, der vom Kunden kommt. Daraus entsteht ein Prozent-Score (0..100)
-- mit Ampel. Der Bogen hängt an PROJEKT UND SKILL (wie die KPI-Konfiguration) —
-- ein Kunde kann für Sales und Support verschiedene Bögen haben. Ein globaler
-- Standard-Bogen (project_id/skill = NULL) greift als Rückfall.
--
-- Struktur wie bei den Feedbackgesprächen (Katalog / Stichprobe / Bewertung je
-- Kriterium) MIT Snapshot-Versionierung: die stabile criterion_id gruppiert über
-- die Zeit, der eingefrorene Wortlaut/Typ/Gewicht in call_scores macht alte
-- Stichproben dauerhaft lesbar, auch wenn der Bogen später geändert wird.
--
-- NUR GERÜST: keine konkreten Kriterien werden geseedet (die Bögen kommen vom
-- Kunden und werden später eingetragen). Geseedet wird nur der globale Default
-- der Ampelgrenzen.
--
-- Kundenzugriff (je Projekt/Skill) folgt in einem späteren Schnitt über eine
-- security-definer-View mit nur freigegebenen Spalten — NICHT über eine Policy auf
-- den Roh-Tabellen (sonst sähe der Kunde interne Kommentare). Vgl. Härtung der
-- Kundenportal-RLS.
--
-- Voraussetzungen (bereits vorhanden): is_admin() (management/hr),
-- get_my_employee_id(). Idempotent. Im Supabase SQL-Editor ausführen.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- §1  Bewertungsbogen (Katalog) — je Projekt UND Skill, NULL/NULL = globaler Standard
--     Rückfall-Reihenfolge (im Frontend): (project_id, skill) → (project_id, NULL)
--     → (NULL, NULL). Fragen werden nie hart gelöscht (active=false), damit
--     criterion_id-Referenzen aus alten Stichproben gültig bleiben.
-- -----------------------------------------------------------------------------
create table if not exists public.call_criteria (
  id           uuid primary key default gen_random_uuid(),
  project_id   text,                               -- NULL = globaler Standard-Bogen
  skill        text,                               -- NULL = alle Skills / Standard
  category     text,                               -- Kategorie/Abschnitt im Bogen
  order_index  int  not null default 0,            -- Sortierung (10er-Schritte)
  prompt       text not null,                      -- Kriterium/Frage
  type         text not null default 'points'
                 check (type in ('points','yesno','grade')),
  max_points   numeric not null default 1,         -- points: max je Kriterium; yesno: 1; grade: 5
  weight       numeric not null default 1,         -- Gewichtung im Gesamt-Score
  allow_na     boolean not null default true,      -- „nicht anwendbar" möglich (aus Score raus)
  hint         text,                               -- optionaler Hilfetext für den Prüfer
  active       boolean not null default true,      -- Soft-Delete
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists idx_call_criteria_lookup
  on public.call_criteria(project_id, skill, active, order_index);

-- -----------------------------------------------------------------------------
-- §2  Stichprobe (eine bewertete Call-Aufnahme, am Mitarbeiter). Projekt/Skill/
--     Zeitraum werden als SNAPSHOT eingefroren, damit die Zuordnung nach einem
--     späteren Projekt-/Skillwechsel stabil bleibt (wie feedback_sessions.project_id
--     und kpi_entries.kw/year). total_pct wird beim Abschließen berechnet und
--     eingefroren.
-- -----------------------------------------------------------------------------
create table if not exists public.call_samples (
  id                uuid primary key default gen_random_uuid(),
  employee_id       uuid not null references public.employees(id) on delete cascade,
  sampled_date      date not null default current_date,
  kw                int,                            -- ISO-KW-Snapshot (getISOWeek)
  year              int,
  project_id        text,                           -- Snapshot Projekt des MA
  skill             text,                           -- Snapshot project_skill des MA
  criteria_scope    text,                           -- welcher Bogen galt: 'project_skill'|'project'|'global'
  call_ref          text,                           -- optional: Call-/Ticket-ID, Datum, Link
  note              text,                           -- Freitext (Gesamteindruck) — INTERN
  total_pct         numeric,                        -- eingefrorener Gesamt-Score 0..100
  status            text not null default 'done'
                      check (status in ('draft','done')),
  conducted_by      uuid references auth.users(id) on delete set null,
  conducted_by_name text,
  conducted_at      timestamptz,
  created_at        timestamptz not null default now()
);
create index if not exists idx_call_samples_emp    on public.call_samples(employee_id, sampled_date desc);
create index if not exists idx_call_samples_period on public.call_samples(project_id, skill, year, kw);

-- -----------------------------------------------------------------------------
-- §3  Bewertung je Kriterium (mit Snapshots). points = erreichte Punkte; der
--     Gesamt-% ergibt sich aus Σ(weight·points/max_points) / Σ(weight) über die
--     nicht-na Zeilen und wird in call_samples.total_pct eingefroren.
-- -----------------------------------------------------------------------------
create table if not exists public.call_scores (
  id                  uuid primary key default gen_random_uuid(),
  sample_id           uuid not null references public.call_samples(id) on delete cascade,
  criterion_id        uuid references public.call_criteria(id) on delete set null,  -- stabile Identität
  order_index         int,
  category_snapshot   text,
  prompt_snapshot     text not null,
  type_snapshot       text not null check (type_snapshot in ('points','yesno','grade')),
  max_points_snapshot numeric not null default 1,
  weight_snapshot     numeric not null default 1,
  points              numeric,                       -- erreichte Punkte (yesno: 0/max; grade gemappt)
  na                  boolean not null default false,-- nicht anwendbar → zählt nicht in den Score
  comment             text,                          -- Kriterien-Kommentar — INTERN
  created_at          timestamptz not null default now()
);
create index if not exists idx_call_scores_sample on public.call_scores(sample_id);

-- -----------------------------------------------------------------------------
-- §4  Ampel-Konfiguration — je Projekt/Skill (Kunden sind unterschiedlich streng),
--     NULL/NULL = globaler Default. Rückfall analog zum Bogen. Grün ab green_min,
--     gelb ab yellow_min, sonst rot. Im Admin änderbar.
-- -----------------------------------------------------------------------------
create table if not exists public.call_score_config (
  id          uuid primary key default gen_random_uuid(),
  project_id  text,                                  -- NULL = globaler Default
  skill       text,                                  -- NULL = globaler Default
  green_min   numeric not null default 90,
  yellow_min  numeric not null default 75,
  updated_at  timestamptz not null default now()
);
-- eine Zeile je (Projekt, Skill); NULLs eindeutig über COALESCE-Index
create unique index if not exists uq_call_score_config
  on public.call_score_config(coalesce(project_id,''), coalesce(skill,''));

-- Globaler Default (nur anlegen, wenn noch keiner existiert)
insert into public.call_score_config (project_id, skill, green_min, yellow_min)
select null, null, 90, 75
where not exists (
  select 1 from public.call_score_config where project_id is null and skill is null
);

-- -----------------------------------------------------------------------------
-- §5  RLS — HR/Management (is_admin) verwalten alles; Mitarbeiter sehen nur die
--     EIGENEN Stichproben/Bewertungen (read-only). Den Bogen und die Config-
--     Schwellen braucht der MA zum Anzeigen der Ampel → Config für alle lesbar,
--     Bogen nur is_admin (Wortlaut liegt als Snapshot in den Bewertungen).
--     Kundenzugriff kommt später über eine security-definer-View.
-- -----------------------------------------------------------------------------
alter table public.call_criteria     enable row level security;
alter table public.call_samples      enable row level security;
alter table public.call_scores       enable row level security;
alter table public.call_score_config enable row level security;

-- Bogen: nur HR/Management
drop policy if exists call_criteria_admin on public.call_criteria;
create policy call_criteria_admin on public.call_criteria
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Stichproben: HR/Management alles …
drop policy if exists call_samples_admin on public.call_samples;
create policy call_samples_admin on public.call_samples
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
-- … Mitarbeiter nur eigene (nur lesen)
drop policy if exists call_samples_own on public.call_samples;
create policy call_samples_own on public.call_samples
  for select to authenticated using (employee_id = public.get_my_employee_id());

-- Bewertungen: HR/Management alles …
drop policy if exists call_scores_admin on public.call_scores;
create policy call_scores_admin on public.call_scores
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
-- … Mitarbeiter nur eigene (über die zugehörige Stichprobe, nur lesen)
drop policy if exists call_scores_own on public.call_scores;
create policy call_scores_own on public.call_scores
  for select to authenticated using (
    exists (select 1 from public.call_samples s
             where s.id = call_scores.sample_id
               and s.employee_id = public.get_my_employee_id()));

-- Ampel-Config: HR/Management schreiben; alle Angemeldeten lesen (nur Schwellen,
-- nicht sensibel — Portale brauchen sie für die Ampelfarbe).
drop policy if exists call_score_config_admin on public.call_score_config;
create policy call_score_config_admin on public.call_score_config
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists call_score_config_read on public.call_score_config;
create policy call_score_config_read on public.call_score_config
  for select to authenticated using (true);

grant select, insert, update, delete on public.call_criteria     to authenticated;
grant select, insert, update, delete on public.call_samples      to authenticated;
grant select, insert, update, delete on public.call_scores       to authenticated;
grant select, insert, update, delete on public.call_score_config to authenticated;

-- -----------------------------------------------------------------------------
-- §6  Realtime — HR-Übersicht/Cockpit aktualisieren live (neue Stichprobe taucht
--     sofort auf). Liegt die Tabelle schon in der Publication, wirft der Befehl
--     einen Fehler → dann einfach diese eine Zeile überspringen.
-- -----------------------------------------------------------------------------
alter publication supabase_realtime add table public.call_samples;
