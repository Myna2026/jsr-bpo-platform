-- Fix: Kunde konnte im Kundenportal nicht bewerten (42501). Die Insert-Policy call_samples_client_insert prüfte
-- „Mitarbeiter gehört zum Kundenprojekt" per Subquery auf employees, die unter der Kunden-RLS 0 Zeilen liefert
-- (Kunde liest MA nur über employees_client_view). Gleiche Falle wie is_emp_in_my_project: Prüfung in eine
-- SECURITY-DEFINER-Funktion, Bedingung inhaltlich unverändert.
create or replace function public.emp_on_project(p_emp uuid, p_project text)
returns boolean language sql stable security definer set search_path = public as $$
  select p_emp is not null and p_project is not null
     and exists (select 1 from public.employees e where e.id = p_emp and e.project_id = p_project);
$$;
revoke all on function public.emp_on_project(uuid, text) from public;
grant execute on function public.emp_on_project(uuid, text) to authenticated;

drop policy if exists call_samples_client_insert on public.call_samples;
create policy call_samples_client_insert on public.call_samples
  for insert to authenticated
  with check (
    rater_kind = 'extern'
    and public.get_my_client_project_id() is not null
    and project_id = public.get_my_client_project_id()
    and public.emp_on_project(employee_id, public.get_my_client_project_id())
  );
