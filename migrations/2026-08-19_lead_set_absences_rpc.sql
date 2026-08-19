-- Leads (projektleiter/teamlead) konnten keine Abwesenheit eintragen ("new row violates RLS").
-- Ursachen: (1) saveEmployeeToDB nutzt upsert -> INSERT-RLS (employees_insert_admin, nur Admin) blockt Leads,
-- bevor die employees_update_lead-Policy/Trigger greifen. (2) Leads haben KEINE SELECT-Policy auf fremde
-- employees-Zeilen (nur maskierte View), darum traefe selbst ein reines UPDATE 0 Zeilen (UPDATE braucht
-- SELECT-Sichtbarkeit). Eine Lead-SELECT-Policy auf der Basistabelle wuerde Gehalt/Bank offenlegen.
-- Loesung: SECURITY-DEFINER-RPC, die NUR absences schreibt und die Projekt-Berechtigung selbst prueft.
create or replace function public.set_employee_absences(p_employee_id uuid, p_absences jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_proj text;
begin
  select project_id into v_proj from public.employees where id = p_employee_id;
  if not found then
    raise exception 'employee not found';
  end if;
  -- Berechtigt: Admin (management/hr/finance) ODER Lead (planner) im SELBEN Projekt wie sein eigener Datensatz.
  if not (
    public.is_management() or public.is_hr() or public.is_finance()
    or (public.is_planner() and v_proj is not distinct from public.get_my_employee_project_id())
  ) then
    raise exception 'not authorized';
  end if;
  update public.employees
     set absences = coalesce(p_absences, '[]'::jsonb), updated_at = now()
   where id = p_employee_id;
end $$;

grant execute on function public.set_employee_absences(uuid, jsonb) to authenticated;
