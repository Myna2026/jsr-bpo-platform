-- =============================================================================
-- HR-Sperre — Schnitt 2b: HR verliert direkten SELECT auf employees          2026-08-05
-- =============================================================================
-- Nach Schnitt 2 war die ANZEIGE maskiert, aber HR konnte public.employees noch
-- DIREKT lesen (Browser-Konsole / Realtime) → Gehälter sichtbar. Das schließt dieser
-- Schnitt: HR liest employees NUR NOCH über die View employees_masked (maskiert).
--
-- WICHTIG (Voraussetzung erfüllt): Das Frontend liest bereits ausschließlich über
-- employees_masked (loadEmployeesFromDB, matchEmployeeToUserSb, Nummernvergabe,
-- MA-Import). Realtime läuft nur noch für Management/Finance. Deshalb bricht der
-- SELECT-Entzug für HR nichts mehr.
--
-- BLEIBT für HR:
--   * UPDATE auf employees (Stammdatenpflege) — der Trigger protect_salary_on_update
--     schützt die 6 Gehalts-/Vertragsspalten hart. Kein Lesezugriff nötig zum Schreiben.
--   * Self-Policies (eigenes Profil lesen/ändern) — unangetastet.
-- Management/Finance behalten vollen direkten SELECT.
--
-- Die bestehende Basis-Policy „HR full access employees" (management/hr/finance, for all)
-- wird durch getrennte Policies ersetzt: SELECT nur mgmt/finance; UPDATE mgmt/finance/hr.
-- Idempotent. Im Supabase SQL-Editor ausführen.
-- =============================================================================

-- Alte kombinierte Policy weg (deckte SELECT+INSERT+UPDATE+DELETE für mgmt/hr/finance ab).
drop policy if exists "HR full access employees" on public.employees;

-- SELECT: nur Management/Finance direkt auf der Basistabelle. HR liest über employees_masked.
drop policy if exists employees_select_full on public.employees;
create policy employees_select_full on public.employees
  for select to authenticated
  using ( public.is_management() or public.is_finance() );

-- INSERT: Management/Finance/HR (HR legt neue MA an / promotet CVs).
drop policy if exists employees_insert_admin on public.employees;
create policy employees_insert_admin on public.employees
  for insert to authenticated
  with check ( public.is_management() or public.is_finance() or public.is_hr() );

-- UPDATE: Management/Finance/HR (HR pflegt Stammdaten/Abwesenheiten). Trigger schützt Gehalt.
drop policy if exists employees_update_admin on public.employees;
create policy employees_update_admin on public.employees
  for update to authenticated
  using      ( public.is_management() or public.is_finance() or public.is_hr() )
  with check ( public.is_management() or public.is_finance() or public.is_hr() );

-- DELETE: nur Management/Finance (HR löscht keine Mitarbeiter).
drop policy if exists employees_delete_admin on public.employees;
create policy employees_delete_admin on public.employees
  for delete to authenticated
  using ( public.is_management() or public.is_finance() );

-- ── Nachweis (mit Deonitas HR-Kennung ausführen) ─────────────────────────────
-- 1) Direktzugriff auf die Basistabelle liefert HÖCHSTENS die EIGENE Zeile (Self-Policy),
--    NICHT die 66 und KEINE fremden Gehälter:
--      select count(*) from public.employees;             -- erwartet: 0 oder 1 (nur eigene)
--      select first_name, last_name, fixed_salary from public.employees
--        where last_name <> '<Deonitas Nachname>';        -- erwartet: 0 Zeilen (kein Fremdzugriff)
-- 2) Die View zeigt alle 66 mit maskierten Gehältern (Edi/Shkurte: fixed_salary NULL, _masked true):
--      select count(*) from public.employees_masked;      -- erwartet: 66
--      select first_name, last_name, fixed_salary, _masked from public.employees_masked
--        where _masked order by last_name;                 -- fixed_salary NULL bei Edi/Shkurte
-- 3) Als Management/Finance liefert der Direktzugriff weiter alle 66 mit Gehalt.
