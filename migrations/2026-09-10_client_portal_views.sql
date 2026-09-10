-- Kundenportal-Ausbau: projekt-gescopte Client-Views für Schichtplan-Check-in, Abwesenheiten und Cockpit-KPIs.
-- Alle security_definer + get_my_client_project_id() → Kunde sieht NUR sein Projekt, keine fremden Daten,
-- keine Gehälter/Bank. Absences ohne Notiz (Datenschutz: Kunde sieht krank/Urlaub + Datum, nicht den Grund).

-- ── employees_client_view: um bereinigte absences erweitern (Typ/Datum, KEINE Notiz) ──
drop view if exists public.employees_client_view;
create view public.employees_client_view
with (security_invoker = false, security_barrier = true) as
select e.id, e.first_name, e.last_name, e."position", e.project_skill as skill, e.city, e.photo_url,
       e.language_level, e.project_id, e.status,
       (select coalesce(jsonb_agg(jsonb_build_object('type',a->>'type','from',a->>'from','to',a->>'to','days',a->'days')),'[]'::jsonb)
          from jsonb_array_elements(coalesce(e.absences,'[]'::jsonb)) a
          where a->>'type' in ('sick','vacation','unpaid')) as absences,
       p.color as project_color
from public.employees e left join public.projects p on p.id = e.project_id
where e.status in ('active','training') and e.project_id = public.get_my_client_project_id();
grant select on public.employees_client_view to authenticated;

-- ── checkins_client_view: Check-in-Status je Schicht/Tag ──
drop view if exists public.checkins_client_view;
create view public.checkins_client_view
with (security_invoker = false, security_barrier = true) as
select c.project_id, c.skill, c.employee_id, c.work_date, c.status, c.arrival, c.departure
from public.shift_checkins c
where c.project_id = public.get_my_client_project_id();
grant select on public.checkins_client_view to authenticated;

-- ── kpi_config_client_view + kpi_entries_client_view: fürs Cockpit ──
drop view if exists public.kpi_config_client_view;
create view public.kpi_config_client_view
with (security_invoker = false, security_barrier = true) as
select id, project_id, skill, name, unit, is_primary from public.kpi_config
where project_id = public.get_my_client_project_id();
grant select on public.kpi_config_client_view to authenticated;

drop view if exists public.kpi_entries_client_view;
create view public.kpi_entries_client_view
with (security_invoker = false, security_barrier = true) as
select e.kpi_id, e.kw, e.year, e.value
from public.kpi_entries e join public.kpi_config c on c.id = e.kpi_id
where c.project_id = public.get_my_client_project_id();
grant select on public.kpi_entries_client_view to authenticated;

notify pgrst, 'reload schema';
