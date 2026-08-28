-- import_aliases war management-only (Policy import_aliases_mgmt = is_management()).
-- Die Call-Importe macht aber Edi (Rolle projektleiter, is_management()=false): er darf weekly_calls
-- und report_forecast seines Projekts schreiben, konnte aber Aliasse weder lesen noch schreiben.
-- Folge: nicht zuordenbare Namen (z. B. "Mergim Geci" != DB "Mergim Gecaj") blieben für ihn
-- unauflösbar, der "Zuordnen/Ignorieren"-Insert wurde still von RLS abgelehnt.
-- Fix: dieselbe projektbezogene Regel wie weekly_calls/report_forecast.
drop policy if exists import_aliases_mgmt on public.import_aliases;
create policy import_aliases_rw on public.import_aliases
  for all
  using      (public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()))
  with check (public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()));
