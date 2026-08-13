-- =============================================================================
-- Wöchentliche Datenablage (Import getrennt vom Bericht)                      2026-08-13
-- =============================================================================
-- Gemeinsamer Ablageort für importierte Wochen-Rohdaten (HolidayCheck u. a.).
-- Der Bericht (presentations) zieht daraus, speichert aber seinen eigenen Snapshot —
-- diese Ablage ist die Quelle, nicht der Bericht. Später docken Forecast/Pausen/mehr an.
--
-- Drei Quellen → drei Fakten-Tabellen, je Mitarbeiter × KW × Jahr:
--   A) Rohdaten-Excel  → weekly_hours   (gearbeitete Stunden je Skill + Pausen Auftraggeber)
--   B) Call-CSV        → weekly_calls   (Answered/Outbound/… + Zeiten in Sekunden)
--   C) Gauges-Excel    → weekly_gauges  (Gesamt%/Anzahl/Dauer/NPS/CSAT)
--
-- Grundsätze:
--   * Erkennung am INHALT (Header) macht das Frontend; hier nur die Ablage.
--   * Nicht zuordenbare Agentennamen werden NICHT zu Fakten (employee_id NOT NULL) —
--     sie landen in data_imports.warnings und werden nach Alias-Pflege neu verarbeitet.
--   * Sales/Support-Trennung über project_skill (unser System), als skill-Snapshot je Zeile.
--   * Re-Import einer Woche: Frontend löscht (project_id,kw,year) und schreibt neu
--     (unique je project/employee/kw/year verhindert Duplikate).
--   * Rohdatei in Storage-Bucket 'weekly-imports' (privat) — Nachvollzug + Re-Parse.
--   * Zugriff nur MANAGEMENT: is_management(). Rohdaten = Arbeitszeiten + Kundendaten =
--     Steuerungsmaterial, keine Personalarbeit → HR/Kunde/MA sehen sie NICHT.
-- Idempotent. Im Supabase SQL-Editor ausführen.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- §1  Import-Metadaten je Upload
-- -----------------------------------------------------------------------------
create table if not exists public.data_imports (
  id               uuid primary key default gen_random_uuid(),
  project_id       text not null,
  source_type      text not null check (source_type in ('rohdaten','calls','gauges')),
  kw               int,
  year             int,
  file_name        text,                         -- Originalname (ändert sich wöchentlich)
  file_hash        text,                         -- Inhalts-Hash (Dedupe / Re-Upload-Erkennung)
  storage_path     text,                         -- Pfad im Bucket 'weekly-imports'
  status           text not null default 'ok' check (status in ('ok','partial','error')),
  warnings         jsonb,                         -- [{type, message, details}] — u. a. nicht zuordenbare Namen
  row_count        int,
  matched_count    int,
  unmatched_count  int,
  uploaded_by      uuid references auth.users(id) on delete set null,
  uploaded_by_name text,
  created_at       timestamptz not null default now()
);
create index if not exists idx_data_imports_scope on public.data_imports(project_id, source_type, year, kw, created_at desc);

-- -----------------------------------------------------------------------------
-- §2  Agent-Name ↔ Mitarbeiter (persistente Alias-Zuordnung je Projekt)
--     Einmal gepflegt, gilt für alle Folgewochen. Namensabweichungen (Schreibweisen).
-- -----------------------------------------------------------------------------
create table if not exists public.import_aliases (
  id              uuid primary key default gen_random_uuid(),
  project_id      text not null,
  alias_name      text not null,                 -- Name genau wie in den Dateien
  employee_id     uuid references public.employees(id) on delete cascade,
  created_by      uuid references auth.users(id) on delete set null,
  created_by_name text,
  created_at      timestamptz not null default now()
);
create unique index if not exists uq_import_aliases on public.import_aliases(project_id, lower(alias_name));

-- -----------------------------------------------------------------------------
-- §3  Fakten A — gearbeitete Stunden + Pausen (Quelle: Rohdaten-Excel)
--     hours = Skill-Formel (Sales: E+BB+AS · Support: E+AQ), in STUNDEN.
--     pause_hours = DH+DI (Auftraggeber), für den Pausen-Gegencheck (nicht Präsentation).
--     raw = Original-Sekunden je Spalte (Nachvollzug/Re-Derive bei Formeländerung).
-- -----------------------------------------------------------------------------
create table if not exists public.weekly_hours (
  id           uuid primary key default gen_random_uuid(),
  import_id    uuid references public.data_imports(id) on delete set null,
  project_id   text not null,
  employee_id  uuid not null references public.employees(id) on delete cascade,
  kw           int not null,
  year         int not null,
  skill        text,                              -- Snapshot project_skill (welche Formel galt)
  hours        numeric,
  pause_hours  numeric,
  raw          jsonb,
  created_at   timestamptz not null default now()
);
create unique index if not exists uq_weekly_hours on public.weekly_hours(project_id, employee_id, kw, year);

-- -----------------------------------------------------------------------------
-- §4  Fakten B — Call-Kennzahlen (Quelle: Call-CSV). Zeiten in Sekunden.
-- -----------------------------------------------------------------------------
create table if not exists public.weekly_calls (
  id             uuid primary key default gen_random_uuid(),
  import_id      uuid references public.data_imports(id) on delete set null,
  project_id     text not null,
  employee_id    uuid not null references public.employees(id) on delete cascade,
  kw             int not null,
  year           int not null,
  answered       int,
  outbound       int,
  no_answer      int,
  avg_handle_sec numeric,
  avg_talk_sec   numeric,
  avg_hold_sec   numeric,
  avg_acw_sec    numeric,
  raw            jsonb,
  created_at     timestamptz not null default now()
);
create unique index if not exists uq_weekly_calls on public.weekly_calls(project_id, employee_id, kw, year);

-- -----------------------------------------------------------------------------
-- §5  Fakten C — Gauges/CSAT (Quelle: Gauges-Excel).
-- -----------------------------------------------------------------------------
create table if not exists public.weekly_gauges (
  id           uuid primary key default gen_random_uuid(),
  import_id    uuid references public.data_imports(id) on delete set null,
  project_id   text not null,
  employee_id  uuid not null references public.employees(id) on delete cascade,
  kw           int not null,
  year         int not null,
  gesamt_pct   numeric,
  anzahl       int,
  dauer_sec    numeric,
  nps          numeric,
  csat         numeric,
  raw          jsonb,
  created_at   timestamptz not null default now()
);
create unique index if not exists uq_weekly_gauges on public.weekly_gauges(project_id, employee_id, kw, year);

-- -----------------------------------------------------------------------------
-- §6  RLS — nur MANAGEMENT (is_management). Rohdaten = Arbeitszeiten + Kundendaten =
--     Steuerungsmaterial, keine Personalarbeit → HR sieht sie NICHT. KEIN Kunde/MA.
-- -----------------------------------------------------------------------------
alter table public.data_imports   enable row level security;
alter table public.import_aliases enable row level security;
alter table public.weekly_hours   enable row level security;
alter table public.weekly_calls   enable row level security;
alter table public.weekly_gauges  enable row level security;

drop policy if exists data_imports_mgmt   on public.data_imports;
create policy data_imports_mgmt   on public.data_imports   for all to authenticated using (public.is_management()) with check (public.is_management());
drop policy if exists import_aliases_mgmt on public.import_aliases;
create policy import_aliases_mgmt on public.import_aliases for all to authenticated using (public.is_management()) with check (public.is_management());
drop policy if exists weekly_hours_mgmt   on public.weekly_hours;
create policy weekly_hours_mgmt   on public.weekly_hours   for all to authenticated using (public.is_management()) with check (public.is_management());
drop policy if exists weekly_calls_mgmt   on public.weekly_calls;
create policy weekly_calls_mgmt   on public.weekly_calls   for all to authenticated using (public.is_management()) with check (public.is_management());
drop policy if exists weekly_gauges_mgmt  on public.weekly_gauges;
create policy weekly_gauges_mgmt  on public.weekly_gauges  for all to authenticated using (public.is_management()) with check (public.is_management());

grant select, insert, update, delete on public.data_imports, public.import_aliases,
  public.weekly_hours, public.weekly_calls, public.weekly_gauges to authenticated;

-- -----------------------------------------------------------------------------
-- §7  Storage-Bucket für Rohdateien (privat, nur is_management)
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('weekly-imports','weekly-imports', false)
  on conflict (id) do nothing;
drop policy if exists "weekly_imports mgmt" on storage.objects;
create policy "weekly_imports mgmt" on storage.objects for all to authenticated
  using      (bucket_id='weekly-imports' and public.is_management())
  with check (bucket_id='weekly-imports' and public.is_management());
