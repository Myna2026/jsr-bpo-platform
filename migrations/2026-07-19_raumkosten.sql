-- =============================================================================
-- Raumkosten: localStorage (jsr_rk_<locId>_<y>_<m> / jsr_rk_overhead_<locId>)
--             -> Supabase                                            2026-07-19
-- =============================================================================
-- Etappe RK1: NUR SCHEMA + RLS. Noch NICHT im Frontend verdrahtet (eigene Etappe RK2).
--   rk_monthly  = erfasste Ist-Beträge je Standort+Monat (Fix-/Variabel-Positionen)
--   rk_overhead = Overhead-/Neutrale-Stellen je Standort (Rolle + zugeordneter MA)
-- Beide haengen an locations.id (Schnitt 1: RK nutzt die echten Standorte).
--
-- Reale Struktur verifiziert gegen hr.html SystemSettingsTab:
--   getRkData/saveRkData (~20135): values = { fix:[{id,label,amount}],
--                                             variable:[{id,label,amount}] }
--   Overhead-Item (~21216): { id, role, emp_id, custom_label } je Position, Liste je
--     Standort. ABWEICHUNG zur Spec: zusaetzliches Feld `custom_label` (bei Rolle
--     'custom' befuellt) -> als Spalte ergaenzt. `seq` steckt im localStorage NICHT
--     (Array-Reihenfolge) -> bei der Migration aus dem Index zu befuellen. `emp_id`
--     ist im localStorage '' wenn leer -> beim Schreiben ''->null (uuid-Spalte).
--
-- RLS (sensible Kostendaten -> eng wie payroll_inputs, KEIN teamlead/projektleiter/
--   mitarbeiter, kein self-read):
--   "read internal" = management/hr/finance
--   "HR write"      = management/hr/finance
--
-- Idempotent (create table / index / policy IF (NOT) EXISTS + drop policy if exists).
-- Anzuwenden im Supabase SQL Editor (hier NICHT ausgefuehrt).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1.1 rk_monthly  (aus jsr_rk_<locId>_<y>_<m>)
-- -----------------------------------------------------------------------------
-- values jsonb = { fix:[{id,label,amount}], variable:[{id,label,amount}] }
create table if not exists public.rk_monthly (
  id          uuid primary key default gen_random_uuid(),
  location_id text references public.locations(id) on delete cascade,
  month       text,                                -- 'YYYY-MM'
  values      jsonb default '{}'::jsonb,
  updated_at  timestamptz default now(),
  unique(location_id, month)
);
create index if not exists idx_rk_monthly_loc on public.rk_monthly(location_id);


-- -----------------------------------------------------------------------------
-- §1.2 rk_overhead  (aus jsr_rk_overhead_<locId>)
-- -----------------------------------------------------------------------------
-- Eine Row je Overhead-Position. emp_id nullable ( set null bei MA-Loeschung).
create table if not exists public.rk_overhead (
  id           uuid primary key default gen_random_uuid(),
  location_id  text references public.locations(id) on delete cascade,
  role         text,                               -- Rollen-Key oder 'custom'
  custom_label text,                               -- Bezeichnung bei role='custom'
  emp_id       uuid references public.employees(id) on delete set null,
  seq          integer,                            -- Reihenfolge (aus Array-Index)
  created_at   timestamptz default now()
);
create index if not exists idx_rk_overhead_loc on public.rk_overhead(location_id);


-- -----------------------------------------------------------------------------
-- §2 RLS — read internal (NUR management/hr/finance) + HR write
-- -----------------------------------------------------------------------------

-- rk_monthly
alter table public.rk_monthly enable row level security;
drop policy if exists "rk_monthly read internal" on public.rk_monthly;
drop policy if exists "rk_monthly HR write" on public.rk_monthly;
create policy "rk_monthly read internal" on public.rk_monthly
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));
create policy "rk_monthly HR write" on public.rk_monthly
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));

-- rk_overhead
alter table public.rk_overhead enable row level security;
drop policy if exists "rk_overhead read internal" on public.rk_overhead;
drop policy if exists "rk_overhead HR write" on public.rk_overhead;
create policy "rk_overhead read internal" on public.rk_overhead
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));
create policy "rk_overhead HR write" on public.rk_overhead
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));


-- =============================================================================
-- Verifikation (auskommentiert)
-- =============================================================================
-- (a) 2 Tabellen:
--     select table_name from information_schema.tables where table_schema='public'
--       and table_name in ('rk_monthly','rk_overhead');
-- (b) RLS-Policies (je 2):
--     select c.relname, count(p.polname) from pg_class c
--      left join pg_policy p on p.polrelid=c.oid
--      where c.relname in ('rk_monthly','rk_overhead') group by c.relname;
-- (c) FKs auf locations (cascade) + employees (set null) + unique(location_id,month):
--     select conname, contype, confdeltype from pg_constraint
--      where conrelid in ('public.rk_monthly'::regclass,'public.rk_overhead'::regclass);
-- =============================================================================
