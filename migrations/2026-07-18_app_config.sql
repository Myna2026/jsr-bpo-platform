-- =============================================================================
-- App-Config: localStorage-Singletons (jsr_*_cfg / *_config) -> Supabase   2026-07-18
-- =============================================================================
-- Etappe C1: NUR SCHEMA + RLS. Noch NICHT im Frontend verdrahtet (eigene Etappe C2).
--
-- Eine generische Key/Value-Tabelle fuer die ~20 Singleton-Config-Blobs (payroll,
-- shift, surcharge, ot, overhead, rk, vacation, holidays, referral, wheel, ai,
-- positions, skills, work_models, absence_types, tab_perms, ...). Jeder localStorage-
-- Key wird eine Zeile: key = Config-Name, value = der bisherige JSON-Blob (jsonb).
-- Whole-Read/Whole-Write, keine Relationen -> generische Tabelle statt ~20 eigener.
-- (Relational abgefragte Configs bleiben eigene Tabellen: kpi_config, forecast_config.)
--
-- RLS: "read internal" (ALLE internen Rollen inkl. mitarbeiter duerfen Configs lesen)
--      + "HR write" (management/hr/finance).
--
-- Idempotent (create table / policy IF (NOT) EXISTS + drop policy if exists).
-- Anzuwenden im Supabase SQL Editor (hier NICHT ausgefuehrt).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1 Tabelle
-- -----------------------------------------------------------------------------
create table if not exists public.app_config (
  key         text primary key,               -- Config-Name (= bisheriger localStorage-Key)
  value       jsonb,                           -- der Config-Blob (Objekt oder Array)
  updated_at  timestamptz default now()
);


-- -----------------------------------------------------------------------------
-- §2 RLS — read internal (alle internen Rollen inkl. mitarbeiter) + HR write
-- -----------------------------------------------------------------------------
alter table public.app_config enable row level security;
drop policy if exists "app_config read all authenticated" on public.app_config;
drop policy if exists "app_config read internal" on public.app_config;
drop policy if exists "app_config HR write" on public.app_config;

create policy "app_config read internal" on public.app_config
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance','teamlead','projektleiter','mitarbeiter']));

create policy "app_config HR write" on public.app_config
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));


-- =============================================================================
-- Verifikation (auskommentiert)
-- =============================================================================
-- (a) Tabelle + Spalten (erwartet 3):
--     select count(*) from information_schema.columns
--      where table_schema='public' and table_name='app_config';           -- 3
-- (b) RLS + 2 Policies:
--     select c.relname, count(p.polname) from pg_class c
--      left join pg_policy p on p.polrelid=c.oid
--      where c.relname='app_config' group by c.relname;                    -- 2
-- =============================================================================
