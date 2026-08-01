-- =============================================================================
-- Kundenportal Dienstplan: shifts_client_view (read-only, spaltenreduziert, projekt-scoped).
-- =============================================================================
-- Der Kunde sieht NUR: Skill, Datum, Mitarbeiter-ID (Name kommt aus employees_client_view),
-- Zeit (shift_value) + Schicht-Label. NICHT: net_hours/gross_hours (interne Stunden),
-- cancel_reason/Pausen (sensibel), updated_by.
--
-- security_definer + Filter in der View → der Kunde braucht KEINEN Basiszugriff auf
-- shift_assignments; die bestehenden HR/Mitarbeiter-Policies auf der Basistabelle bleiben
-- unberührt (kein Eingriff dort). Zeilen-Scope: nur eigenes Projekt (get_my_client_project_id).
--
-- Abgesagte Schichten (shift.canceled) werden ausgeschlossen — die Person arbeitet dann nicht,
-- und der Grund (krank/unbezahlt) ist ohnehin nichts für den Kunden.
-- Im Supabase SQL-Editor ausführen.
-- =============================================================================

drop view if exists public.shifts_client_view;

create view public.shifts_client_view
with (security_invoker = false, security_barrier = true)
as
select
  project_id,
  skill,
  employee_id,
  work_date,
  shift_value,
  label
from public.shift_assignments
where project_id = public.get_my_client_project_id()
  and shift_value is not null
  and coalesce((shift->>'canceled')::boolean, false) = false;

grant select on public.shifts_client_view to authenticated;
