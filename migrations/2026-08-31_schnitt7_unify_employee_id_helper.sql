-- Teil 3: get_my_employee_id (mit staff_number-Fallback) ist die robustere Fassung. my_employee_id (ohne Fallback)
-- delegiert jetzt dorthin → EINE Implementierung, kein Drift. Betrifft 14 Self-Policies; sie bekommen den Fallback
-- (findet den eigenen MA auch über staff_number, wenn employee_id fehlt) — additiv/robuster. is_admin (mgmt/hr) und
-- is_management (nur mgmt) bleiben GETRENNT: sie sind NICHT redundant, bedeuten Verschiedenes.
create or replace function public.my_employee_id()
returns uuid language sql stable security definer set search_path=public as $$
  select public.get_my_employee_id()
$$;
