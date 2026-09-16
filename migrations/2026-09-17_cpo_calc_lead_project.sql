-- CPO-Kalkulator auch für den Projektleiter des Mandats (Ylli führt Giganetz, User 2026-09-17).
-- Additiv: zweite permissive Policy, Lead-only-Rollen sehen und pflegen NUR die Kalkulation ihres Projekts
-- (project_id = eigenes Projekt aus employees). Management-Policy cpo_calc_mgmt_all bleibt unverändert.
-- Frontend: Menüpunkt für Leads, deren Projekt ein Mandat in shared/cpo-calc.js hat (team.cpoLead).
drop policy if exists cpo_calc_lead_project on public.cpo_calc_configs;
create policy cpo_calc_lead_project on public.cpo_calc_configs
  for all to authenticated
  using (public.is_lead_only() and project_id = public.get_my_employee_project_id())
  with check (public.is_lead_only() and project_id = public.get_my_employee_project_id());
