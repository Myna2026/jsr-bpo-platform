-- Reisewelt-Demo: KPI-Client-Views fürs Cockpit (projekt-scoped, security_definer wie die anderen *_client_view).
drop view if exists public.kpi_config_client_view;
create view public.kpi_config_client_view
with (security_invoker = false, security_barrier = true) as
select id, project_id, skill, name, unit, is_primary from public.kpi_config
where project_id = public.get_my_client_project_id();
grant select on public.kpi_config_client_view to authenticated;

drop view if exists public.kpi_entries_client_view;
create view public.kpi_entries_client_view
with (security_invoker = false, security_barrier = true) as
select e.kpi_id, e.kw, e.year, e.value
from public.kpi_entries e join public.kpi_config c on c.id = e.kpi_id
where c.project_id = public.get_my_client_project_id();
grant select on public.kpi_entries_client_view to authenticated;
