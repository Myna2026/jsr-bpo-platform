-- =============================================================================
-- Schulungsplaene: localStorage (jsr_plans_v3) -> Supabase   2026-07-18
-- =============================================================================
-- Etappe S1: NUR SCHEMA + RLS. Noch NICHT im Frontend verdrahtet (eigene Etappe).
--   training_plans = 1 Row pro Schulungs-Batch.
--
-- Reale Struktur (Union aus TRAINING_PLANS_INIT hr.html:819 + TrainingPlanModal-Form
-- 4930 + savePlan 5119). Abweichung zur Recon-Spec: zusaetzliches Feld `notes`
-- (die Modal-Form pflegt es, INIT/Recon nicht). Alle uebrigen Felder wie spezifiziert.
--   confirmed_ids = Liste von MA-IDs -> jsonb (robuster als uuid[]: toleriert
--   Legacy-IDs vor der MA-Migration, kein Typ-Coercion-Fehler beim Schreiben).
--   start_date/end_date = 'YYYY-MM-DD' (date-Inputs) -> date.
--
-- RLS nach projects-Muster: "read internal" (ALLE internen Rollen inkl. mitarbeiter,
-- Schulungsplanung ist nicht vertraulich) + "HR write" (management/hr/finance).
--
-- Idempotent (create table / index / policy IF (NOT) EXISTS + drop policy if exists).
-- Anzuwenden im Supabase SQL Editor (hier NICHT ausgefuehrt).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1 Tabelle
-- -----------------------------------------------------------------------------
create table if not exists public.training_plans (
  id             uuid primary key default gen_random_uuid(),
  project_id     text references public.projects(id) on delete cascade,
  name           text,
  start_date     date,
  end_date       date,
  planned_count  integer,
  mode           text,                          -- 'Vor Ort' | 'Hybrid' | ...
  skill_focus    text,
  primary_skill  text,
  confirmed_ids  jsonb default '[]'::jsonb,      -- [emp_id, ...] bestaetigte Teilnehmer
  avg_salary     numeric,
  status         text,                           -- 'planned' | ...
  notes          text,                           -- interne Notizen (Modal-Feld)
  created_at     timestamptz default now()
);
create index if not exists idx_training_plans_project on public.training_plans(project_id);


-- -----------------------------------------------------------------------------
-- §2 RLS — read internal (alle internen Rollen inkl. mitarbeiter) + HR write
-- -----------------------------------------------------------------------------
alter table public.training_plans enable row level security;
drop policy if exists "training_plans read all authenticated" on public.training_plans;
drop policy if exists "training_plans read internal" on public.training_plans;
drop policy if exists "training_plans HR write" on public.training_plans;

create policy "training_plans read internal" on public.training_plans
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance','teamlead','projektleiter','mitarbeiter']));

create policy "training_plans HR write" on public.training_plans
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));


-- =============================================================================
-- Verifikation (auskommentiert)
-- =============================================================================
-- (a) Tabelle + Spalten (erwartet 14):
--     select count(*) from information_schema.columns
--      where table_schema='public' and table_name='training_plans';       -- 14
-- (b) RLS + 2 Policies:
--     select c.relname, count(p.polname) from pg_class c
--      left join pg_policy p on p.polrelid=c.oid
--      where c.relname='training_plans' group by c.relname;                -- 2
-- (c) FK project_id -> projects(id), on delete cascade:
--     select conname, confdeltype from pg_constraint
--      where conrelid='public.training_plans'::regclass and contype='f';   -- 'c'
-- =============================================================================
