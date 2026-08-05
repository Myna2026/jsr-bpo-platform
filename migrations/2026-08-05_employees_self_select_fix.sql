-- =============================================================================
-- HOTFIX: HR/jeder muss die EIGENE employees-Zeile direkt lesen können      2026-08-05
-- =============================================================================
-- Nach 2026-08-05_employees_hr_select_revoke sah HR employees nur noch über
-- is_management()/is_finance(). Der MA-Portal-Login (loadOwnEmployeeFromDB,
-- mitarbeiter.html) liest aber die EIGENE Zeile direkt auf der Basistabelle
-- (eq('id', employee_id)). Griff die separate Self-Policy für HR nicht, kam 0
-- Zeilen → „Kein Mitarbeiter-Datensatz verknüpft" → Login scheitert.
--
-- Fix: employees_select_full um einen Self-Zweig ergänzen. Sicher — der Betrachter
-- sieht damit NUR die eigene Zeile zusätzlich (id = get_my_employee_id()), keine
-- fremden Gehälter. Management/Finance behalten Vollzugriff; HR liest alles andere
-- weiterhin über die maskierende View employees_masked.
-- Idempotent. Im Supabase SQL-Editor ausführen.
-- =============================================================================

drop policy if exists employees_select_full on public.employees;
create policy employees_select_full on public.employees
  for select to authenticated
  using (
    public.is_management()
    or public.is_finance()
    or id = public.get_my_employee_id()
  );

-- Prüfung: als HR (Deonita) liefert der Direktzugriff jetzt genau die eigene Zeile,
-- fremde Gehälter bleiben gesperrt:
--   select count(*) from public.employees;                              -- erwartet: 1 (eigene)
--   select first_name, fixed_salary from public.employees;             -- nur eigene Zeile
--   select first_name, last_name, fixed_salary, _masked from public.employees_masked; -- alle 66, Edi/Shkurte maskiert
