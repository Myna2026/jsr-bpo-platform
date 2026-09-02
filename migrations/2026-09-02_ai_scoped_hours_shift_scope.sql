-- Anna unterzählte gelieferte Stunden: ai_scoped.daily_hours/weekly_hours nutzten die KPI-Regel je AGENT
-- (perm_emp_row_ok 'kpi'), die Nicht-Agenten (Teamleiter/Projektleiter/Trainer) durchfallen lässt, obwohl sie
-- Stunden liefern. Stunden gehören aber JEDEM, der arbeitet. Umstellung auf die PROJEKTBEZOGENE Regel, die auch
-- die echte RLS der Tabelle nutzt: perm 'shift', Projekt-Scope, HR ausgeschlossen (wie not is_hr() in der RLS,
-- hier mit ai_uid nachgebaut). Damit stimmt Anna mit dem Cockpit überein.

create or replace view ai_scoped.daily_hours as
  select id, import_id, project_id, employee_id, work_date, skill, hours, pause_hours, sales_calls, created_at
  from public.daily_hours t
  where public.perm_mode(public.ai_uid(),'shift') <> 'none'
    and public.perm_proj_ok(public.ai_uid(),'shift', project_id, null)
    and not exists (select 1 from public.app_users au where au.user_id=public.ai_uid() and au.role_keys && array['hr']::text[]);

create or replace view ai_scoped.weekly_hours as
  select id, import_id, project_id, employee_id, kw, year, skill, hours, pause_hours, raw, created_at, sales_calls
  from public.weekly_hours t
  where public.perm_mode(public.ai_uid(),'shift') <> 'none'
    and public.perm_proj_ok(public.ai_uid(),'shift', project_id, null)
    and not exists (select 1 from public.app_users au where au.user_id=public.ai_uid() and au.role_keys && array['hr']::text[]);
