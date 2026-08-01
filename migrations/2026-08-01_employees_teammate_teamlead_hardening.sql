-- =============================================================================
-- employees-Härtung: über-breite Spaltenzugriffe für Mitarbeiter + Teamlead weg.
-- =============================================================================
-- Gleiches Muster wie das Kunden-Leck: Basis-Policies gaben zeilen-gescopten
-- SELECT auf die VOLLE employees-Tabelle (alle Spalten inkl. fixed_salary, bank,
-- contract) — per Direktabfrage UND Realtime lesbar.
--   * "Employee sees teammates" (25i): SCHARF — verknüpfte MA (Edi/Shkurte) konnten
--     die Gehälter ihrer Projekt-Kollegen abfragen. Der (b)-Zweig
--     (employees.role_keys && {management,hr}) griff nie (Feld ist bei allen leer)
--     → die projektübergreifende HR/Management-Sichtbarkeit war ohnehin tot.
--   * "Teamlead sees project employees" (25a/25d): LATENT — sobald ein Teamleiter
--     einen Zugang bekommt, saehe er die Löhne seines Teams. Widerspraeche dem
--     sperrbaren HR-Payroll-Tab (Teamleiter sollen KEINE Gehälter sehen).
--
-- Fix (View-only, wie beim Kunden):
--   1) Beide Basis-Policies droppen. Self-Policies ("Employee sees/updates own
--      profile") bleiben — eigenes Profil (inkl. eigenem Gehalt) ist legitim.
--   2) employees_team_view auf security_definer + eingebauten Projekt-Filter;
--      toter (b)-Zweig entfaellt. Nur die bekannten 12 sicheren Spalten (kein Gehalt).
--   3) MA-Portal-Team-Realtime entfernt (mitarbeiter.html) — lieferte volle Zeilen.
-- Im Supabase SQL-Editor ausführen. get_my_employee_project_id() existiert aus 25i.
-- =============================================================================

-- 1) Über-breite Basis-Policies entfernen.
drop policy if exists "Employee sees teammates" on public.employees;
drop policy if exists "Teamlead sees project employees" on public.employees;

-- 2) Kollegen-View: security_definer + Filter in der View selbst (kein RLS-Zweig mehr noetig).
drop view if exists public.employees_team_view;

create view public.employees_team_view
with (security_invoker = false, security_barrier = true)
as
select
  id,
  first_name,
  last_name,
  position,
  role_keys,
  project_id,
  status,
  photo_url,
  extra->>'function'      as function,
  extra->>'project_skill' as project_skill,
  extra->>'primary_skill' as primary_skill,
  extra->>'photo_color'   as photo_color
from public.employees
where status in ('active', 'training')
  and project_id = public.get_my_employee_project_id();

grant select on public.employees_team_view to authenticated;
