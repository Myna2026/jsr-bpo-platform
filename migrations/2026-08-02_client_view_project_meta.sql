-- =============================================================================
-- Kundenportal: View-Erweiterung — Projekt-Skill korrekt + Projektfarbe + Stadt.
-- =============================================================================
-- Konsolidiert (eine Migration statt drei), nach Durchsicht ALLER Felder, die
-- client.html aus den beiden Kunden-Views liest:
--
-- 1) employees_client_view.skill lieferte bisher die flache Spalte `skill` — die
--    ist leer. Der operative Wert ist `project_skill` (Sales/Support). Deshalb
--    `project_skill as skill` ausliefern. KEINE CV-/Zusatz-Skills (Ticketing o. Ä.).
-- 2) `city` ergänzen (Standort der Person, z. B. Prishtina) für Karte + Detail.
-- 3) `project_color` ergänzen (aus projects.color, Join über project_id) — für die
--    Dienstplan-Balken in Projektfarbe. Auf BEIDEN Kunden-Views, damit Team- und
--    Dienstplan-Ansicht dieselbe Farbe haben.
--
-- Unverändert: Status-Filter (nur active/training → Ex-Mitarbeiter bleiben draußen),
-- Projekt-Scope get_my_client_project_id(), security_definer + security_barrier,
-- KEIN Basiszugriff des Kunden auf employees/shift_assignments.
-- Im Supabase SQL-Editor ausführen. get_my_client_project_id() existiert aus 25e.
-- =============================================================================

-- ── employees_client_view ────────────────────────────────────────────────────
drop view if exists public.employees_client_view;

create view public.employees_client_view
with (security_invoker = false, security_barrier = true)
as
select
  e.id,
  e.first_name,
  e.last_name,
  e.position,
  e.project_skill as skill,     -- operativer Projekt-Skill (Sales/Support), nicht die leere skill-Spalte
  e.city,
  e.photo_url,
  e.language_level,
  e.project_id,
  e.status,
  p.color as project_color
from public.employees e
left join public.projects p on p.id = e.project_id
where e.status in ('active', 'training')
  and e.project_id = public.get_my_client_project_id();

grant select on public.employees_client_view to authenticated;

-- ── shifts_client_view (identisch zu 2026-08-01, plus project_color) ──────────
drop view if exists public.shifts_client_view;

create view public.shifts_client_view
with (security_invoker = false, security_barrier = true)
as
select
  s.project_id,
  s.skill,
  s.employee_id,
  s.work_date,
  s.shift_value,
  s.label,
  p.color as project_color
from public.shift_assignments s
left join public.projects p on p.id = s.project_id
where s.project_id = public.get_my_client_project_id()
  and s.shift_value is not null
  and coalesce((s.shift->>'canceled')::boolean, false) = false;

grant select on public.shifts_client_view to authenticated;
