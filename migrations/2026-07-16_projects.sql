-- =============================================================================
-- Projekte: localStorage (jsr_projects_v1) -> Supabase (relational)   2026-07-16
-- =============================================================================
-- NUR SCHEMA + RLS + SEED. Noch NICHT im Frontend verdrahtet (eigene Etappe).
-- IDs = bestehende Slug-Strings aus PROJECT_UUIDS (hr.html:416) -> alle
-- project_id-Referenzen (employees.project_id, jsr_perf_v1, jsr_forecast_v1,
-- jsr_plans_v3, wfp_plan_<id>_...) bleiben gueltig, KEIN Re-Keying.
--
-- RLS pro Tabelle: 2 Policies
--   1) "read internal" -> for select: alle internen Rollen (management/hr/finance/
--      teamlead/projektleiter/mitarbeiter) via app_users. KEIN Kunde (role 'kunde').
--   2) "HR write"      -> for all: nur management/hr/finance via app_users
--      (Schreib-Muster analog "HR full access payslips",
--       backend/migrations/27a_payslips_schema.sql:114-129)
--
-- Anzuwenden im Supabase SQL Editor (hier NICHT ausgefuehrt).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1 Tabellen  (alle id/project_id als text/uuid; projects-PK = Slug)
-- -----------------------------------------------------------------------------
create table if not exists public.projects (
  id                     text primary key,                 -- Slug, z.B. proj_hc_a1b2c3d4
  name                   text,
  client                 text,
  status                 text,
  location               text,
  rate_active            numeric,
  rate_training          numeric,
  billing_mode           text,
  monthly_flat           numeric,
  ai_translation_enabled boolean,
  created_at             timestamptz default now()
);

create table if not exists public.project_skills (
  id            uuid primary key default gen_random_uuid(),
  project_id    text references public.projects(id) on delete cascade,
  key           text,
  label         text,
  rate          numeric null,
  rate_training numeric null,
  seq           int,
  unique(project_id, key)
);

create table if not exists public.project_skill_profiles (
  id         uuid primary key default gen_random_uuid(),
  project_id text,
  skill_key  text,
  label      text,
  seq        int,
  foreign key (project_id) references public.projects(id) on delete cascade
);

create table if not exists public.project_profiles (
  id         uuid primary key default gen_random_uuid(),
  project_id text references public.projects(id) on delete cascade,
  label      text,
  seq        int
);

create table if not exists public.project_trainings (
  id         uuid primary key default gen_random_uuid(),
  project_id text references public.projects(id) on delete cascade,
  tkey       text,
  name       text,
  weeks      int,
  seq        int
);


-- -----------------------------------------------------------------------------
-- §2 RLS — pro Tabelle: read internal (interne Rollen, kein Kunde) + HR-write
-- -----------------------------------------------------------------------------
alter table public.projects enable row level security;
drop policy if exists "projects read all authenticated" on public.projects;
drop policy if exists "projects read internal" on public.projects;
drop policy if exists "projects HR write" on public.projects;
create policy "projects read internal" on public.projects
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance','teamlead','projektleiter','mitarbeiter']));
create policy "projects HR write" on public.projects
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));

alter table public.project_skills enable row level security;
drop policy if exists "project_skills read all authenticated" on public.project_skills;
drop policy if exists "project_skills read internal" on public.project_skills;
drop policy if exists "project_skills HR write" on public.project_skills;
create policy "project_skills read internal" on public.project_skills
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance','teamlead','projektleiter','mitarbeiter']));
create policy "project_skills HR write" on public.project_skills
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));

alter table public.project_skill_profiles enable row level security;
drop policy if exists "project_skill_profiles read all authenticated" on public.project_skill_profiles;
drop policy if exists "project_skill_profiles read internal" on public.project_skill_profiles;
drop policy if exists "project_skill_profiles HR write" on public.project_skill_profiles;
create policy "project_skill_profiles read internal" on public.project_skill_profiles
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance','teamlead','projektleiter','mitarbeiter']));
create policy "project_skill_profiles HR write" on public.project_skill_profiles
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));

alter table public.project_profiles enable row level security;
drop policy if exists "project_profiles read all authenticated" on public.project_profiles;
drop policy if exists "project_profiles read internal" on public.project_profiles;
drop policy if exists "project_profiles HR write" on public.project_profiles;
create policy "project_profiles read internal" on public.project_profiles
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance','teamlead','projektleiter','mitarbeiter']));
create policy "project_profiles HR write" on public.project_profiles
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));

alter table public.project_trainings enable row level security;
drop policy if exists "project_trainings read all authenticated" on public.project_trainings;
drop policy if exists "project_trainings read internal" on public.project_trainings;
drop policy if exists "project_trainings HR write" on public.project_trainings;
create policy "project_trainings read internal" on public.project_trainings
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance','teamlead','projektleiter','mitarbeiter']));
create policy "project_trainings HR write" on public.project_trainings
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));


-- -----------------------------------------------------------------------------
-- §3 Seed — die 4 echten Projekte (Slugs aus PROJECT_UUIDS, hr.html:416)
--     Grunddaten aus PROJECTS_INIT (hr.html:493-503). Idempotent (on conflict).
--     Giganetz-Skills (Retention, 1st Level) laut Vorgabe; Raten unbekannt -> null
--     (Giganetz = monthly_flat, Skill-Raten fuer die Abrechnung irrelevant).
--     Condor + Fabletics: keine Skills.
-- -----------------------------------------------------------------------------
insert into public.projects
  (id, name, client, status, location, rate_active, rate_training, billing_mode, monthly_flat, ai_translation_enabled) values
  ('proj_hc_a1b2c3d4', 'Holidaycheck',    'Holidaycheck AG', 'active', 'Tirana',    null, null, 'productive_hours', null, false),
  ('proj_gn_e5f6a7b8', 'Giganetz',        'Giganetz GmbH',   'active', 'Prishtina', null, null, 'monthly_flat',     null, false),
  ('proj_cd_c9d0e1f2', 'Condor Holidays', 'Condor GmbH',     'active', 'Tirana',    null, null, 'productive_hours', null, false),
  ('proj_fb_a3b4c5d6', 'Fabletics',       'Fabletics Inc.',  'active', 'Prishtina', null, null, 'monthly_flat',     null, false)
on conflict (id) do update set
  name=excluded.name, client=excluded.client, status=excluded.status, location=excluded.location,
  rate_active=excluded.rate_active, rate_training=excluded.rate_training,
  billing_mode=excluded.billing_mode, monthly_flat=excluded.monthly_flat,
  ai_translation_enabled=excluded.ai_translation_enabled;

insert into public.project_skills (project_id, key, label, rate, rate_training, seq) values
  ('proj_hc_a1b2c3d4', 'support',   'Support',   null, null, 1),
  ('proj_hc_a1b2c3d4', 'sales',     'Sales',     null, null, 2),
  ('proj_gn_e5f6a7b8', 'retention', 'Retention', null, null, 1),
  ('proj_gn_e5f6a7b8', '1st_level', '1st Level', null, null, 2)
on conflict (project_id, key) do update set
  label=excluded.label, rate=excluded.rate, rate_training=excluded.rate_training, seq=excluded.seq;

-- Fremd-/Dummy-Projekte entfernen (Cascade raeumt skills/profiles/trainings mit).
delete from public.projects
 where id not in ('proj_hc_a1b2c3d4','proj_gn_e5f6a7b8','proj_cd_c9d0e1f2','proj_fb_a3b4c5d6');


-- =============================================================================
-- Verifikation (auskommentiert)
-- =============================================================================
-- (a) 5 Tabellen:
--     select table_name from information_schema.tables
--     where table_schema='public'
--       and table_name in ('projects','project_skills','project_skill_profiles','project_profiles','project_trainings');
-- (b) RLS + je 2 Policies:
--     select c.relname, count(p.polname) from pg_class c
--     left join pg_policy p on p.polrelid=c.oid
--     where c.relname like 'project%' group by c.relname;   -- je 2
-- (c) Seed: 4 Projekte, 4 Skills:
--     select count(*) from public.projects;                 -- 4
--     select project_id, key from public.project_skills order by project_id, seq;
--       -- proj_gn_e5f6a7b8: retention, 1st_level ; proj_hc_a1b2c3d4: support, sales
-- =============================================================================
