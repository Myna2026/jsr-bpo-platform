-- Reisewelt-Demo: checkins_client_view — der Kunde sieht den Check-in-Status seines Projekts (projekt-scoped,
-- security_definer, wie shifts_client_view). Nur Status + Zeiten, keine sensiblen Spalten.
-- (Nur auf Myna. Falls später produktiv gewünscht, hier ins Live-Schema übernehmen.)
drop view if exists public.checkins_client_view;
create view public.checkins_client_view
with (security_invoker = false, security_barrier = true)
as
select c.project_id, c.skill, c.employee_id, c.work_date, c.status, c.arrival, c.departure, c.source
from public.shift_checkins c
where c.project_id = public.get_my_client_project_id();
grant select on public.checkins_client_view to authenticated;
