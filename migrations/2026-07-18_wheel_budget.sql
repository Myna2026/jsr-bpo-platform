-- =============================================================================
-- Gluecksrad: Monatsbudget + Dreh-Historie + Sonderaktionen -> Supabase  2026-07-18
-- =============================================================================
-- Etappe G1: NUR SCHEMA + RLS. Noch NICHT im Frontend verdrahtet (Logik = G2).
--   wheel_budgets  = Monatsbudget (1 Row pro Monat)
--   wheel_specials = Sonderaktionen (Topf + Tranchen)
--   wheel_spins    = jeder Dreh (Nachvollziehbarkeit + Lohnabrechnung), 1/Tag/MA
-- Reihenfolge wg. FK: budgets, specials, dann spins (spins.special_id -> specials).
--
-- RLS-Muster:
--   wheel_budgets/wheel_specials -> "read internal" (ALLE internen Rollen inkl.
--     mitarbeiter; der MA muss Budget/Aktionen sehen) + "HR write" (management/hr/finance).
--   wheel_spins -> wie kpi_entries: "read internal" OHNE mitarbeiter + "self read"
--     (emp_id = eigene employee_id) -> der MA sieht NUR eigene Gewinne + "HR write".
--
-- Idempotent (create table / index / policy IF (NOT) EXISTS + drop policy if exists).
-- Anzuwenden im Supabase SQL Editor (hier NICHT ausgefuehrt).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1 Tabellen
-- -----------------------------------------------------------------------------
create table if not exists public.wheel_budgets (
  month       text primary key,               -- 'YYYY-MM'
  amount      numeric,                          -- Monatsbudget (z.B. 1000)
  created_at  timestamptz default now()
);

create table if not exists public.wheel_specials (
  id             uuid primary key default gen_random_uuid(),
  label          text,
  start_date     date,
  end_date       date,
  total_amount   numeric,                       -- Gesamttopf
  tranche_amount numeric,                       -- Einzelgewinn (z.B. 500)
  tranche_count  integer,                       -- Anzahl (z.B. 2)
  created_at     timestamptz default now()
);

create table if not exists public.wheel_spins (
  id          uuid primary key default gen_random_uuid(),
  emp_id      uuid references public.employees(id) on delete cascade,
  spin_date   date,
  amount      numeric,                           -- 0 = kein Gewinn
  source      text,                              -- 'normal' | 'special'
  special_id  uuid references public.wheel_specials(id) on delete set null,
  created_at  timestamptz default now(),
  unique(emp_id, spin_date)                      -- ein Dreh pro Tag pro MA
);
create index if not exists idx_wheel_spins_emp   on public.wheel_spins(emp_id);
create index if not exists idx_wheel_spins_date  on public.wheel_spins(spin_date);


-- -----------------------------------------------------------------------------
-- §2 RLS
-- -----------------------------------------------------------------------------
-- wheel_budgets: read internal (inkl. mitarbeiter) + HR write
alter table public.wheel_budgets enable row level security;
drop policy if exists "wheel_budgets read internal" on public.wheel_budgets;
drop policy if exists "wheel_budgets HR write" on public.wheel_budgets;
create policy "wheel_budgets read internal" on public.wheel_budgets
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance','teamlead','projektleiter','mitarbeiter']));
create policy "wheel_budgets HR write" on public.wheel_budgets
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));

-- wheel_specials: read internal (inkl. mitarbeiter) + HR write
alter table public.wheel_specials enable row level security;
drop policy if exists "wheel_specials read internal" on public.wheel_specials;
drop policy if exists "wheel_specials HR write" on public.wheel_specials;
create policy "wheel_specials read internal" on public.wheel_specials
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance','teamlead','projektleiter','mitarbeiter']));
create policy "wheel_specials HR write" on public.wheel_specials
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));

-- wheel_spins: read internal OHNE mitarbeiter + self read (eigene Zeilen) + HR write
alter table public.wheel_spins enable row level security;
drop policy if exists "wheel_spins read internal" on public.wheel_spins;
drop policy if exists "wheel_spins self read" on public.wheel_spins;
drop policy if exists "wheel_spins HR write" on public.wheel_spins;
create policy "wheel_spins read internal" on public.wheel_spins
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance','teamlead','projektleiter']));
create policy "wheel_spins self read" on public.wheel_spins
  for select to authenticated
  using (emp_id = (select employee_id from app_users where user_id = auth.uid()));
create policy "wheel_spins HR write" on public.wheel_spins
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));


-- =============================================================================
-- Verifikation (auskommentiert)
-- =============================================================================
-- (a) 3 Tabellen:
--     select table_name from information_schema.tables where table_schema='public'
--       and table_name in ('wheel_budgets','wheel_specials','wheel_spins');
-- (b) Policies: wheel_budgets=2, wheel_specials=2, wheel_spins=3:
--     select c.relname, count(p.polname) from pg_class c
--      left join pg_policy p on p.polrelid=c.oid
--      where c.relname like 'wheel_%' group by c.relname;
-- (c) FKs auf wheel_spins (emp_id cascade, special_id set null) + unique(emp_id,spin_date):
--     select conname, contype, confdeltype from pg_constraint
--      where conrelid='public.wheel_spins'::regclass;
-- =============================================================================
