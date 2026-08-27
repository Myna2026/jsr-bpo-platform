-- KI-Datenzugriff Schnitt 3 (Admin-UI): eine autoritative Uebersicht je Back-Office-Nutzer.
-- Liefert Rolle/Position/Projekt-Kontext + is_full + gespeicherten Override + Rollen-Default + effektiv.
-- Management-only (leere Menge sonst). Kein Client-Drift: Default/Effektiv kommen aus den DB-Funktionen.
create or replace function public.ai_access_overview()
returns table(
  user_id uuid, full_name text, email text, role_keys text[], employee_id uuid,
  is_full boolean, stored jsonb, default_prefs jsonb, effective jsonb
)
language sql stable security definer set search_path=public as $$
  select a.user_id, a.full_name, u.email, a.role_keys, a.employee_id,
    public.ai_is_full(a.user_id),
    (select p.settings from public.ai_access_prefs p where p.user_id = a.user_id),
    public.ai_default_prefs(a.user_id),
    public.ai_effective_prefs(a.user_id)
  from public.app_users a
  left join auth.users u on u.id = a.user_id
  where coalesce(a.active, true) and public.is_management()
$$;
grant execute on function public.ai_access_overview() to authenticated, service_role;
