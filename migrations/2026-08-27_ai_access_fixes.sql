-- KI-Datenzugriff, Korrekturen 2026-08-27:
-- 1) Thorsten meldet sich als consulting@25hrs.net an (tschroeppe@icloud.com existiert nicht) -> feste Voll-Liste korrigieren.
-- 2) ai_access_overview: Kundenzugaenge (Rolle kunde) und rollenlose Karteileichen ausblenden.
-- 3) Eva Duqi: versehentlicher Override identisch zum Rollen-Standard -> entfernen (Standard greift wieder).

-- 1) Feste Voll-Zugriffe: Thorsten korrekt per aktiver Login-Adresse.
create or replace function public.ai_is_full(p_uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from auth.users u where u.id = p_uid
      and lower(u.email) = any (array['info@mynaai.de','sh.cikaqi@25hrs.net','r.gore@tiramu.de','consulting@25hrs.net'])
  );
$$;

-- 2) Uebersicht nur fuer echte Back-Office-Zugaenge: mindestens eine Rolle, keine Kundenrolle.
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
    and array_length(a.role_keys, 1) is not null
    and not ('kunde' = any(a.role_keys))
$$;

-- 3) Overrides, die exakt dem Rollen-Standard entsprechen, sind keine echten Overrides -> aufraeumen (u.a. Eva).
delete from public.ai_access_prefs p where p.settings = public.ai_default_prefs(p.user_id);
