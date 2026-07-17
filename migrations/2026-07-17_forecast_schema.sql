-- =============================================================================
-- Forecast-Modell: Abrechnungsfelder + Verfuegbarkeit + Config   2026-07-17
-- =============================================================================
-- Baut auf migrations/2026-07-16_projects.sql (+ _cols) auf.
--   §1 Abrechnungsfelder auf projects UND project_skills (entweder/oder je nach
--      Skill-Existenz: Skill gepflegt -> Skill-Werte, sonst Projekt-Werte).
--   §2 employees.forecast_include (Overhead aus dem Forecast nehmen).
--   §3 forecast_config — erste Config-Tabelle in Supabase (Single-Row).
--   §4 RLS fuer forecast_config (Muster der Projekt-Tabellen). projects/
--      project_skills/employees haben schon RLS -> neue Spalten automatisch
--      abgedeckt, dort KEINE RLS-Aenderung.
-- Idempotent (add column / create table / policy IF (NOT) EXISTS).
--
-- Anzuwenden im Supabase SQL Editor (hier NICHT ausgefuehrt).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1 Abrechnungsfelder — dieselben Spalten auf projects UND project_skills
-- -----------------------------------------------------------------------------
alter table public.projects add column if not exists billing_type      text;      -- hourly|minute|case|cpo|flat_per_agent
alter table public.projects add column if not exists minute_rate       numeric;
alter table public.projects add column if not exists case_price        numeric;
alter table public.projects add column if not exists case_aht_sec      numeric;
alter table public.projects add column if not exists cpo_amount        numeric;
alter table public.projects add column if not exists cpo_per_hour      numeric;
alter table public.projects add column if not exists flat_per_agent    numeric;
alter table public.projects add column if not exists productive_hours  numeric;    -- Override; leer = werktage×work_hours
alter table public.projects add column if not exists efficiency_pct    numeric;    -- leer = 100 (FE-Default)
alter table public.projects add column if not exists training_mode     text;       -- rate|flat
alter table public.projects add column if not exists training_flat     numeric;

alter table public.project_skills add column if not exists billing_type      text;      -- hourly|minute|case|cpo|flat_per_agent
alter table public.project_skills add column if not exists minute_rate       numeric;
alter table public.project_skills add column if not exists case_price        numeric;
alter table public.project_skills add column if not exists case_aht_sec      numeric;
alter table public.project_skills add column if not exists cpo_amount        numeric;
alter table public.project_skills add column if not exists cpo_per_hour      numeric;
alter table public.project_skills add column if not exists flat_per_agent    numeric;
alter table public.project_skills add column if not exists productive_hours  numeric;    -- Override; leer = werktage×work_hours
alter table public.project_skills add column if not exists efficiency_pct    numeric;    -- leer = 100 (FE-Default)
alter table public.project_skills add column if not exists training_mode     text;       -- rate|flat
alter table public.project_skills add column if not exists training_flat     numeric;


-- -----------------------------------------------------------------------------
-- §2 employees — Verfuegbarkeit im Forecast
-- -----------------------------------------------------------------------------
alter table public.employees add column if not exists forecast_include boolean;   -- null/true = berücksichtigt, false = raus (Overhead)


-- -----------------------------------------------------------------------------
-- §3 forecast_config — erste Config-Tabelle in Supabase (Single-Row)
-- -----------------------------------------------------------------------------
create table if not exists public.forecast_config (
  id                       text primary key default 'singleton',
  gross_monthly_hours      numeric,                                       -- Brutto-Override (loest GROSS=160 ab)
  count_holidays_as_workday boolean default true,
  deduct_absence_types     text[] default array['vacation','sick','unpaid'],
  default_efficiency_pct   numeric default 100,
  updated_at               timestamptz default now()
);
insert into public.forecast_config (id) values ('singleton') on conflict (id) do nothing;


-- -----------------------------------------------------------------------------
-- §4 RLS forecast_config — Muster der Projekt-Tabellen (read internal + HR write)
--     projects/project_skills/employees: KEINE RLS-Aenderung (neue Spalten sind
--     durch die bestehenden Policies automatisch abgedeckt).
-- -----------------------------------------------------------------------------
alter table public.forecast_config enable row level security;
drop policy if exists "forecast_config read all authenticated" on public.forecast_config;
drop policy if exists "forecast_config read internal" on public.forecast_config;
drop policy if exists "forecast_config HR write" on public.forecast_config;
create policy "forecast_config read internal" on public.forecast_config
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance','teamlead','projektleiter','mitarbeiter']));
create policy "forecast_config HR write" on public.forecast_config
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));


-- =============================================================================
-- Verifikation (auskommentiert)
-- =============================================================================
-- (a) §1 Spalten auf beiden Tabellen (je 13):
--     select table_name, count(*) from information_schema.columns
--      where table_schema='public' and table_name in ('projects','project_skills')
--        and column_name in ('billing_type','hourly_rate','minute_rate','case_price',
--          'case_aht_sec','cpo_amount','cpo_per_hour','flat_per_agent','productive_hours',
--          'efficiency_pct','training_mode','training_rate','training_flat')
--      group by table_name;   -- je 13
-- (b) §2: employees.forecast_include existiert (boolean).
-- (c) §3: select * from public.forecast_config;   -- 1 Zeile ('singleton', count_holidays_as_workday=true)
-- (d) §4: RLS + 2 Policies:
--     select c.relname, count(p.polname) from pg_class c
--      left join pg_policy p on p.polrelid=c.oid
--      where c.relname='forecast_config' group by c.relname;   -- 2
-- =============================================================================
