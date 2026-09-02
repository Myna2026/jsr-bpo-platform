-- Datenabfrage (Anna) scheiterte bei „geleistete Stunden im August tagesgenau": nlquery_exec läuft nur über
-- ai_scoped-Views (search_path=ai_scoped), und ai_scoped.daily_hours gab es nicht (nur weekly_hours = Wochen-View).
-- Ergo: scoped Tagesebene ergänzen, gleiche Zeilen-/Gehaltsscope wie ai_scoped.weekly_hours (perm 'kpi', ai_uid).
create or replace view ai_scoped.daily_hours as
  select id, import_id, project_id, employee_id, work_date, skill, hours, pause_hours, sales_calls, created_at
  from public.daily_hours t
  where case
    when employee_id is not null then exists (
      select 1 from public.employees e
      where e.id = t.employee_id
        and public.perm_emp_row_ok(public.ai_uid(),'kpi', e.id, e.project_id, e.skill, e."position"))
    else public.perm_proj_ok(public.ai_uid(),'kpi', project_id, skill)
  end;
grant select on ai_scoped.daily_hours to nlquery_ro;
