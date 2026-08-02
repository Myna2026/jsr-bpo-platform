-- =============================================================================
-- Kundenportal: photo_color in employees_client_view aufnehmen (Personenfarbe/Avatar).
-- =============================================================================
-- Der Avatar eines Mitarbeiters ist seine stabile Personenfarbe. Quelle: das im HR
-- gepflegte Feld employees.photo_color, sonst (leer) ein stabiler Hash aus der ID im
-- Frontend. Damit die View den HR-Wert liefern kann, wird die Spalte ergänzt.
--
-- Vollständige Neu-Definition der View (idempotent) = alle bisherigen Spalten aus
-- 2026-08-02_client_view_project_meta.sql PLUS photo_color. Diese Migration allein
-- genügt für employees_client_view. photo_color ist unkritisch (nur ein Farbwert).
-- shifts_client_view bleibt unverändert (project_color dort aus der project_meta-Migration).
-- Im Supabase SQL-Editor ausführen.
-- =============================================================================

drop view if exists public.employees_client_view;

create view public.employees_client_view
with (security_invoker = false, security_barrier = true)
as
select
  e.id,
  e.first_name,
  e.last_name,
  e.position,
  e.project_skill as skill,
  e.city,
  e.photo_url,
  e.photo_color,
  e.language_level,
  e.project_id,
  e.status,
  p.color as project_color
from public.employees e
left join public.projects p on p.id = e.project_id
where e.status in ('active', 'training')
  and e.project_id = public.get_my_client_project_id();

grant select on public.employees_client_view to authenticated;
