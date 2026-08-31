-- Zielmenge für die Handlung remind_missing_bank, perm-gescopt auf den BESTÄTIGENDEN (p_actor). lena_scan() ist
-- admin-gated, läuft aber für service_role (auth.uid() null) durch → alle bank_fehlt; perm_proj_ok(p_actor,...)
-- schneidet auf dessen Projekte (mgmt/hr alle, Lead nur eigenes). Nur MA mit E-Mail.
create or replace function public.agent_missing_bank_targets(p_actor uuid)
returns table(employee_id uuid, email text, first_name text)
language sql stable security definer set search_path=public as $$
  select e.id, e.email, e.first_name
  from public.lena_scan() ls
  join public.employees e on e.id = ls.employee_id
  where ls.category = 'bank_fehlt'
    and public.perm_proj_ok(p_actor, 'emp', e.project_id, null)
    and coalesce(nullif(e.email,''),'') <> ''
$$;
grant execute on function public.agent_missing_bank_targets(uuid) to service_role;
