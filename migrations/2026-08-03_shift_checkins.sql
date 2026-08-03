-- =============================================================================
-- Check-in als IST-Ebene zum Schichtplan (Schnitt 1: Tabelle + RLS)      2026-08-03
-- =============================================================================
-- EIGENE Tabelle (nicht ein Feld in shift_assignments): Plan bleibt in der Zelle,
-- Ist kommt DANEBEN, beide vergleichbar. Bezug 1:1 auf die Plan-Zelle über den
-- Vierer-Key (project_id, skill, employee_id, work_date) — KEIN FK auf
-- shift_assignments (ein Ist-Eintrag ohne Plan-Zelle soll möglich bleiben).
--
-- Kommen und Gehen getrennt. Herkunft am Eintrag (manual jetzt, timeclock später);
-- `source` ist Teil des PK, damit manual+timeclock je Tag koexistieren können
-- (Prinzip wie bei den Pausen). "Noch nicht bestätigt" = KEIN Row.
--
-- RLS-Grundsatz (Nachweis statt Behauptung, Prüfabfragen unten):
--   Lesen:    Management/HR alles · Mitarbeiter nur EIGENE · Teamleiter/Projektleiter
--             nur EIGENES Projekt.
--   Schreiben: Management/HR alles · Teamleiter/Projektleiter nur EIGENES Projekt.
--             Mitarbeiter dürfen NICHT schreiben (nur lesen).
--
-- Abhängigkeit: is_planner()/is_admin()/get_my_employee_id()/get_my_employee_project_id()
-- existieren (Shift-Planning + 25i). Im Supabase SQL-Editor ausführen.
-- =============================================================================

create table if not exists public.shift_checkins (
  project_id        text not null,
  skill             text not null default 'all',
  employee_id       uuid not null references public.employees(id) on delete cascade,
  work_date         date not null,
  status            text not null,                    -- present|late|early|sick|no_show
  arrival           time,                             -- Kommen (Ist), optional
  departure         time,                             -- Gehen (Ist), optional  (getrennt: späterer Start = evtl. längeres Bleiben)
  reason            text,                             -- Grund bei Abweichung
  source            text not null default 'manual',  -- manual|timeclock (Herkunft am Eintrag)
  confirmed_by      uuid references auth.users(id) on delete set null,
  confirmed_by_name text,
  confirmed_at      timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  primary key (project_id, skill, employee_id, work_date, source),
  constraint shift_checkins_status_chk check (status in ('present','late','early','sick','no_show')),
  constraint shift_checkins_source_chk check (source in ('manual','timeclock'))
);

-- Check-in-Bereich (heutiger Tag je Projekt/Skill) + Plan-Zellen-Glyph / MA-Lesen:
create index if not exists idx_checkin_proj_date on public.shift_checkins (project_id, skill, work_date);
create index if not exists idx_checkin_emp_date  on public.shift_checkins (employee_id, work_date);

alter table public.shift_checkins enable row level security;

-- ── Lesen ────────────────────────────────────────────────────────────────────
drop policy if exists sc_select on public.shift_checkins;
create policy sc_select on public.shift_checkins
  for select to authenticated
  using (
    public.is_admin()
    or employee_id = public.get_my_employee_id()
    or (public.is_planner() and project_id = public.get_my_employee_project_id())
  );

-- ── Schreiben (insert/update/delete): kein Selbst-Check-in durch Mitarbeiter ──
drop policy if exists sc_insert on public.shift_checkins;
create policy sc_insert on public.shift_checkins
  for insert to authenticated
  with check (
    public.is_admin()
    or (public.is_planner() and project_id = public.get_my_employee_project_id())
  );

drop policy if exists sc_update on public.shift_checkins;
create policy sc_update on public.shift_checkins
  for update to authenticated
  using (
    public.is_admin()
    or (public.is_planner() and project_id = public.get_my_employee_project_id())
  )
  with check (
    public.is_admin()
    or (public.is_planner() and project_id = public.get_my_employee_project_id())
  );

drop policy if exists sc_delete on public.shift_checkins;
create policy sc_delete on public.shift_checkins
  for delete to authenticated
  using (
    public.is_admin()
    or (public.is_planner() and project_id = public.get_my_employee_project_id())
  );

grant select, insert, update, delete on public.shift_checkins to authenticated;
