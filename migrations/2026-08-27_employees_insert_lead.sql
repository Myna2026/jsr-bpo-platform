-- Projektleiter konnten Mitarbeiter ÄNDERN (employees_update_lead), aber nicht ANLEGEN: beim Übernehmen eines
-- Bewerbers scheiterte der INSERT an employees_insert_admin (nur management/finance/hr). Postgres prüft beim
-- Einfügen die INSERT-Regel, nicht die UPDATE-Regel (gleiches Muster wie damals bei den Abwesenheiten).
-- Fix: INSERT-Policy für Leads, exakt gespiegelt zur Update-Policy — nur für das eigene Projekt.
drop policy if exists employees_insert_lead on public.employees;
create policy employees_insert_lead on public.employees for insert to authenticated
  with check (is_planner() and (project_id = get_my_employee_project_id()));
