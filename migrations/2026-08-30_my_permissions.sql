-- Rechte Schnitt 3: der Aufrufer holt seine aufgelösten Rechte für alle Bereiche in einem Aufruf.
-- Das Frontend liest daraus die Menü-Sichtbarkeit der 12 sauberen Bereiche (System bleibt vorerst auf
-- der alten Rollenlogik, weil er zu viel bündelt und das harte Admin-Gate nicht verwässert werden darf).
create or replace function public.my_permissions()
returns jsonb language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_object_agg(a.key, public.perm(auth.uid(), a.key)), '{}'::jsonb)
  from public.permission_areas a;
$$;
revoke all on function public.my_permissions() from public;
grant execute on function public.my_permissions() to authenticated;
