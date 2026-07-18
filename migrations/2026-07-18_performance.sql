-- =============================================================================
-- Performance: localStorage (jsr_kpi_cfg_v1 / jsr_perf_v1) -> Supabase   2026-07-18
-- =============================================================================
-- Etappe P1: NUR SCHEMA + RLS. Noch NICHT im Frontend verdrahtet (eigene Etappe).
--   kpi_config  = KPI-Definitionen, skill-basiert  (heute jsr_kpi_cfg_v1)
--   kpi_entries = Ist-Werte, MA x Woche x KPI       (heute jsr_perf_v1)
--
-- kpi_config.id bleibt ein Slug-String (z.B. 'kpi_cvr') -> die kpi_id-Referenz
-- in kpi_entries bleibt gueltig, KEIN Re-Keying.
-- kpi_entries.emp_id = uuid -> FK auf employees(id) (uuid), on delete cascade.
--
-- RLS pro Tabelle: 2 Policies (Muster exakt von public.projects gespiegelt)
--   1) "read internal" -> for select: alle internen Rollen (management/hr/finance/
--      teamlead/projektleiter/mitarbeiter) via app_users. KEIN Kunde (role 'kunde').
--   2) "HR write"      -> for all: nur management/hr/finance via app_users.
--
-- Idempotent (create table / policy IF (NOT) EXISTS + drop policy if exists).
-- Anzuwenden im Supabase SQL Editor (hier NICHT ausgefuehrt).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1 Tabellen
-- -----------------------------------------------------------------------------
create table if not exists public.kpi_config (
  id          text primary key,                 -- Slug, z.B. 'kpi_cvr'
  project_id  text,                              -- nullable (KPI gilt ggf. projektweit)
  skill       text,
  name        text,
  type        text,                              -- percent|number|...
  unit        text,
  thresholds  jsonb,                             -- Array {min,max,label,color,icon}
  created_at  timestamptz default now()
);

create table if not exists public.kpi_entries (
  id          uuid primary key default gen_random_uuid(),
  emp_id      uuid references public.employees(id) on delete cascade,
  kw          int,
  year        int,
  kpi_id      text,
  value       numeric,
  entered_by  text,
  ts          timestamptz default now()
);


-- -----------------------------------------------------------------------------
-- §2 RLS — pro Tabelle: read internal (interne Rollen, kein Kunde) + HR-write
-- -----------------------------------------------------------------------------
alter table public.kpi_config enable row level security;
drop policy if exists "kpi_config read all authenticated" on public.kpi_config;
drop policy if exists "kpi_config read internal" on public.kpi_config;
drop policy if exists "kpi_config HR write" on public.kpi_config;
create policy "kpi_config read internal" on public.kpi_config
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance','teamlead','projektleiter','mitarbeiter']));
create policy "kpi_config HR write" on public.kpi_config
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));

alter table public.kpi_entries enable row level security;
drop policy if exists "kpi_entries read all authenticated" on public.kpi_entries;
drop policy if exists "kpi_entries read internal" on public.kpi_entries;
drop policy if exists "kpi_entries HR write" on public.kpi_entries;
create policy "kpi_entries read internal" on public.kpi_entries
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance','teamlead','projektleiter','mitarbeiter']));
create policy "kpi_entries HR write" on public.kpi_entries
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));


-- =============================================================================
-- Verifikation (auskommentiert)
-- =============================================================================
-- (a) 2 Tabellen:
--     select table_name from information_schema.tables
--     where table_schema='public' and table_name in ('kpi_config','kpi_entries');
-- (b) RLS + je 2 Policies:
--     select c.relname, count(p.polname) from pg_class c
--     left join pg_policy p on p.polrelid=c.oid
--     where c.relname in ('kpi_config','kpi_entries') group by c.relname;   -- je 2
-- (c) FK kpi_entries.emp_id -> employees(id), on delete cascade:
--     select conname, confdeltype from pg_constraint
--     where conrelid='public.kpi_entries'::regclass and contype='f';        -- confdeltype='c'
-- =============================================================================
