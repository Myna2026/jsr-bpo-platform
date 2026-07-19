-- =============================================================================
-- Standorte: localStorage (jsr_locations_v1 / jsr_location_monthly_v1 /
--            jsr_spaces_v1) -> Supabase                              2026-07-19
-- =============================================================================
-- Etappe L1: NUR SCHEMA + RLS. Noch NICHT im Frontend verdrahtet (eigene Etappe L2).
--   locations        = Standort-Stammdaten (1 Row pro Standort)
--   location_monthly = variable Monatskosten (1 Row pro Standort+Monat)
--   spaces           = Raeume/Spaces je Standort (Grundrisse + Sitzplaetze)
--
-- Reihenfolge wg. FK: locations zuerst, dann location_monthly + spaces
-- (beide referenzieren locations.id).
--
-- Reale Struktur verifiziert gegen hr.html LocationsView (Seed 17904, newLocTemplate
-- 18010, getFixedTotal 17961, getMonthlyExtra 17969, saveSpace 18420). Abweichungen
-- zur Recon-Spec siehe Kommentare bei §1.3 (spaces).
--
-- RLS nach projects/training_plans-Muster: "read internal" (ALLE internen Rollen
-- inkl. mitarbeiter) + "HR write" (management/hr/finance).
--
-- Idempotent (create table / index / policy IF (NOT) EXISTS + drop policy if exists).
-- Anzuwenden im Supabase SQL Editor (hier NICHT ausgefuehrt).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1.1 locations  (aus jsr_locations_v1)
-- -----------------------------------------------------------------------------
-- id = App-Slug ('loc_tirana' bzw. 'loc_'+timestamp) -> text, damit bestehende
--      IDs beim Import verlustfrei erhalten bleiben (kein uuid).
-- capacity     jsonb = { total_sqm, seats_total, seats_used }
-- costs_fixed  jsonb = { rent, utilities_electricity, utilities_water, internet,
--                        cleaning, insurance, management, other_fixed }
-- costs_custom jsonb = [ { label, amount }, ... ]  (im Seed/Template nicht gesetzt,
--                        wird erst im Edit-Modal befuellt -> default '[]')
create table if not exists public.locations (
  id           text primary key,                 -- 'loc_tirana' | 'loc_'+ts
  name         text,
  country      text,
  flag         text,
  color        text,
  address      text,
  active       boolean default true,
  capacity     jsonb default '{}'::jsonb,
  costs_fixed  jsonb default '{}'::jsonb,
  costs_custom jsonb default '[]'::jsonb,
  notes        text,
  created_at   timestamptz default now()
);


-- -----------------------------------------------------------------------------
-- §1.2 location_monthly  (aus jsr_location_monthly_v1)
-- -----------------------------------------------------------------------------
-- localStorage-Form: monthlyCosts[locId][month] = { team_events, repairs, supplies,
--   travel, other, other_note }. Hier flach: 1 Row je (location_id, month),
--   das Kosten-Objekt landet in `values`.
-- id ist neu vergeben (kein Quell-ID im localStorage) -> uuid ok.
create table if not exists public.location_monthly (
  id          uuid primary key default gen_random_uuid(),
  location_id text references public.locations(id) on delete cascade,
  month       text,                               -- 'YYYY-MM'
  values      jsonb default '{}'::jsonb,           -- { team_events, repairs, supplies, travel, other, other_note }
  updated_at  timestamptz default now(),           -- Zusatz: Monatskosten werden editiert (nicht in Spec, harmlos)
  unique(location_id, month)
);
create index if not exists idx_location_monthly_loc on public.location_monthly(location_id);


-- -----------------------------------------------------------------------------
-- §1.3 spaces  (aus jsr_spaces_v1)
-- -----------------------------------------------------------------------------
-- ABWEICHUNG zur Spec: reale Struktur hat KEIN flaches `seats`, sondern `floors`
--   (Stockwerke) -> jsonb-Array [ { name, plan_url, seats:[ {id, ...} ] } ].
--   Sitzplaetze haengen also PRO Stockwerk unter floors[].seats, nicht direkt am
--   Space. plan_url = Base64-Grundrissbild (kann gross werden; jsonb vertraegt es).
-- id = App-Slug ('sp_'+timestamp) -> text (analog locations), damit bestehende IDs
--   verlustfrei importieren. (Spec sah uuid vor; text vermeidet ID-Remap.)
create table if not exists public.spaces (
  id          text primary key,                   -- 'sp_'+ts
  location_id text references public.locations(id) on delete cascade,
  name        text,
  description text,
  sqm         numeric,
  floors      jsonb default '[]'::jsonb,           -- [ { name, plan_url, seats:[...] } ]
  created_at  timestamptz default now()
);
create index if not exists idx_spaces_loc on public.spaces(location_id);


-- -----------------------------------------------------------------------------
-- §2 RLS — read internal (alle internen Rollen inkl. mitarbeiter) + HR write
-- -----------------------------------------------------------------------------

-- locations
alter table public.locations enable row level security;
drop policy if exists "locations read internal" on public.locations;
drop policy if exists "locations HR write" on public.locations;
create policy "locations read internal" on public.locations
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance','teamlead','projektleiter','mitarbeiter']));
create policy "locations HR write" on public.locations
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));

-- location_monthly
alter table public.location_monthly enable row level security;
drop policy if exists "location_monthly read internal" on public.location_monthly;
drop policy if exists "location_monthly HR write" on public.location_monthly;
create policy "location_monthly read internal" on public.location_monthly
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance','teamlead','projektleiter','mitarbeiter']));
create policy "location_monthly HR write" on public.location_monthly
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));

-- spaces
alter table public.spaces enable row level security;
drop policy if exists "spaces read internal" on public.spaces;
drop policy if exists "spaces HR write" on public.spaces;
create policy "spaces read internal" on public.spaces
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance','teamlead','projektleiter','mitarbeiter']));
create policy "spaces HR write" on public.spaces
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
--       and table_name in ('locations','location_monthly','spaces');
-- (b) RLS-Policies (je 2): locations=2, location_monthly=2, spaces=2:
--     select c.relname, count(p.polname) from pg_class c
--      left join pg_policy p on p.polrelid=c.oid
--      where c.relname in ('locations','location_monthly','spaces') group by c.relname;
-- (c) FKs auf locations (on delete cascade) + unique(location_id,month):
--     select conname, contype, confdeltype from pg_constraint
--      where conrelid in ('public.location_monthly'::regclass,'public.spaces'::regclass);
-- =============================================================================
