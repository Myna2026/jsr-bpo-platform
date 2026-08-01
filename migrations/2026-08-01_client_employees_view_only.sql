-- =============================================================================
-- Kundenportal-Härtung: voller Spaltenzugriff des Kunden auf employees ENTFERNEN.
-- =============================================================================
-- Kern des Datenschutz-Lecks: Die 25e-Policy gab dem Kunden zeilen-gescopten
-- SELECT auf die BASISTABELLE public.employees — also ALLE Spalten (fixed_salary,
-- hourly_rate, bank, contract, notes, id_number …). Lesbar per Direktabfrage
-- (from('employees').select('*')) UND per Realtime-Full-Row. Die View (25f) war
-- kein Schutz, weil security_invoker=true den Basiszugriff voraussetzte.
--
-- Fix (View-only):
--   1) 25e-Policy droppen  → Kunde hat KEINEN Basiszugriff mehr auf employees.
--   2) View auf security_definer (läuft mit Owner-Rechten, umgeht Basis-RLS) mit
--      eingebautem Projekt-Filter get_my_client_project_id() + nur sicheren Spalten.
--      audios/videos raus, language_level rein (Sprachen gleich mitgefaltet → 1 Umbau).
--   3) Realtime im Kundenportal ist im Frontend entfernt (client.html).
-- Danach kann der Kunde employees NUR noch über die spaltenreduzierte View lesen.
-- Im Supabase SQL-Editor ausführen. get_my_client_project_id() existiert aus 25e.
-- =============================================================================

-- 1) Kunden-Basiszugriff auf employees ENTFERNEN (das eigentliche Leck).
drop policy if exists "Client sees employees on their project" on public.employees;

-- 2) View neu: security_definer (KEIN security_invoker), Filter in der View selbst.
drop view if exists public.employees_client_view;

create view public.employees_client_view
with (security_invoker = false, security_barrier = true)
as
select
  id,
  first_name,
  last_name,
  position,
  skill,
  photo_url,
  language_level,
  project_id,
  status
from public.employees
where status in ('active', 'training')
  and project_id = public.get_my_client_project_id();

grant select on public.employees_client_view to authenticated;
