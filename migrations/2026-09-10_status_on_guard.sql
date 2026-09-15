-- Schnitt 3: employee_status_on gegen Status-Enumeration absichern. Die Funktion ist SECURITY DEFINER (umgeht RLS),
-- also war sie fuer JEDEN Angemeldeten aufrufbar (auch MA-/Kundenportal). Kopfzahlen sind eine Management-Sicht →
-- Rollen-Gate direkt in die Abfrage: Nicht-Admins bekommen keine Zeilen.
create or replace function public.employee_status_on(p_date date)
returns table(employee_id uuid, status text)
language sql stable security definer set search_path=public as $$
  select distinct on (p.employee_id) p.employee_id, p.status
  from public.employee_status_periods p
  where p.from_date <= p_date and (p.to_date is null or p.to_date > p_date)
    and (public.is_management() or public.is_hr() or public.is_finance())
  order by p.employee_id, p.from_date desc
$$;
