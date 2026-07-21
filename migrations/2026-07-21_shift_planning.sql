-- =============================================================================
-- Schichtplanung → DB  (Etappe 2: nur Schema + RLS, kein Frontend-Code) 2026-07-21
-- =============================================================================
-- Letzter localStorage-Bereich: der Schichtplan muss in die DB, damit alle
-- (5 Manager) UND die Mitarbeiter im mitarbeiter.html-Portal dasselbe sehen.
-- Heute liegt alles origin-getrennt im localStorage (hr.tive360.de vs.
-- mitarbeiter.tive360.de) → niemand sieht den Plan des anderen.
--
-- Diese Migration legt NUR die Tabellen + RLS an. Es liest/schreibt noch KEIN
-- Frontend darauf → null Laufzeitwirkung, risikofrei einspielbar.
--
-- Ablösung der localStorage-Keys:
--   wfp_plan_<proj>_<skill>_<YYYY>_<MM>   → shift_assignments (eine Zeile/Zelle)
--   wfp_ifc_* / wfp_dfc_*                 → forecast_demand
--   jsr_plan_profiles                     → app_config-Blob (KEINE Tabelle, Etappe 3)
--   jsr_shift_cfg (Schicht-Vorlagen)      → bereits über app_config synced
--
-- Design-Entscheidung: shift_assignments ist NORMALISIERT (eine Zeile pro
-- Projekt/Skill/Mitarbeiter/Tag). Grund: Bei 5 Managern würde ein Monatsblob
-- konkurrierende Edits überschreiben (last-write-wins killt fremde Zellen).
-- Zeilen-pro-Zelle = Upsert je Zelle → Manager A (Emp X) und B (Emp Y)
-- kollidieren nie.
--
-- Idempotent (if not exists / drop policy if exists / or replace). Anzuwenden
-- im Supabase SQL Editor (hier NICHT ausgeführt).
-- Voraussetzung: schema_auth.sql (app_users, is_admin), employees,
-- vacation_requests_schema.sql (get_my_employee_id).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1 Helper: is_planner() — wer darf Schichten planen (schreiben) und alle sehen.
--    Planer = aktive app_user mit einer Workforce-Rolle. Analog is_admin(),
--    aber breiter (Teamleiter/Projektleiter planen mit). SECURITY DEFINER, damit
--    die Policy-Subquery nicht an app_users-RLS scheitert.
-- -----------------------------------------------------------------------------
create or replace function public.is_planner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.app_users
     where user_id = auth.uid()
       and active
       and role_keys && array['management','hr','teamlead','projektleiter']::text[]
  );
$$;
revoke all    on function public.is_planner() from public;
grant execute on function public.is_planner() to authenticated;


-- -----------------------------------------------------------------------------
-- §2 shift_assignments — eine Zeile pro (Projekt, Skill, Mitarbeiter, Tag).
--    project_id/skill sind Client-Strings (z. B. 'proj_hc_support' / 'support' /
--    'all') → text, kein FK auf projects. employee_id = employees.id (uuid),
--    identisch zu emp.id im Frontend und zu vacation_requests.employee_id.
-- -----------------------------------------------------------------------------
create table if not exists public.shift_assignments (
  project_id      text not null,
  skill           text not null default 'all',
  employee_id     uuid not null references public.employees(id) on delete cascade,
  work_date       date not null,
  -- die zugewiesene Schicht (aus dem s_<emp>_<ds>-Zellenobjekt):
  shift_id        text,             -- Referenz auf jsr_shift_cfg-Vorlage (id)
  label           text,             -- z. B. "Frueh lang"
  shift_value     text,             -- "08:00-17:30"
  value2          text,             -- 2. Block bei Split-Schicht
  net_hours       numeric,          -- bezahlte Netto-Stunden
  gross_hours     numeric,          -- Brutto-Stunden
  pause_duration  numeric,
  pause_paid      boolean,
  split           boolean not null default false,
  -- Intraday-Coverage-Raster (die i_<emp>_<ds>_<slot>-Werte) als kompaktes jsonb:
  slots           jsonb,
  -- Audit:
  updated_by      uuid references auth.users(id) on delete set null,
  updated_by_name text,
  updated_at      timestamptz not null default now(),
  primary key (project_id, skill, employee_id, work_date)
);

-- Schneller Zugriff für „meine Schichten" (MeinPlanView) und Monatsabfragen:
create index if not exists idx_shift_emp_date  on public.shift_assignments (employee_id, work_date);
create index if not exists idx_shift_proj_date on public.shift_assignments (project_id, skill, work_date);

alter table public.shift_assignments enable row level security;

-- Planer: alles lesen + schreiben.
drop policy if exists sa_planner_all on public.shift_assignments;
create policy sa_planner_all on public.shift_assignments
  for all to authenticated
  using (public.is_planner())
  with check (public.is_planner());

-- Mitarbeiter: nur die EIGENEN Schichten lesen (fürs mitarbeiter.html-Portal).
-- Mehrere permissive SELECT-Policies werden mit OR kombiniert.
drop policy if exists sa_self_select on public.shift_assignments;
create policy sa_self_select on public.shift_assignments
  for select to authenticated
  using (employee_id = public.get_my_employee_id());

grant select, insert, update, delete on public.shift_assignments to authenticated;


-- -----------------------------------------------------------------------------
-- §3 forecast_demand — eine Zeile pro (Projekt, Skill, Tag).
--    Forecast ist ein reines Planungs-Artefakt → nur Planer, kein Self-Read.
--    ifc = Inbound je 30-Min-Slot (Array), dfc = Tages-Demand (FTE/Std.).
-- -----------------------------------------------------------------------------
create table if not exists public.forecast_demand (
  project_id  text not null,
  skill       text not null default 'all',
  work_date   date not null,
  ifc         jsonb,            -- Array Slotwerte
  dfc         numeric,          -- Tages-Demand
  updated_by  uuid references auth.users(id) on delete set null,
  updated_at  timestamptz not null default now(),
  primary key (project_id, skill, work_date)
);

alter table public.forecast_demand enable row level security;

drop policy if exists fd_planner_all on public.forecast_demand;
create policy fd_planner_all on public.forecast_demand
  for all to authenticated
  using (public.is_planner())
  with check (public.is_planner());

grant select, insert, update, delete on public.forecast_demand to authenticated;


-- -----------------------------------------------------------------------------
-- §4 Realtime — damit Planänderungen bei allen offenen Sessions live erscheinen.
--    Idempotent über pg_publication_tables-Check (kein Fehler bei Doppel-Lauf).
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public' and tablename = 'shift_assignments'
  ) then
    alter publication supabase_realtime add table public.shift_assignments;
  end if;

  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public' and tablename = 'forecast_demand'
  ) then
    alter publication supabase_realtime add table public.forecast_demand;
  end if;
end $$;
