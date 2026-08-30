-- „Wer sieht was": KI-Datenrechte-Spalte aus dem MODELL ableiten (perm/user_permissions), nicht mehr aus dem
-- alten ai_access_overview. Sonst zeigt sie Rollen-Standard, wo laengst ein user_permissions-Override gilt
-- (Ylli, Hajrije) — irrefuehrend. Nur Anzeige-Metadaten (Scope-Form), keine echten Gehaltswerte. Management-only.
-- Repraesentativer Datenbereich = 'emp' (Menschen-Daten), auf den die KI im Kern zugreift.
create or replace function public.ai_scope_overview()
returns table(user_id uuid, email text, is_full boolean, projects text, project_ids jsonb,
              direction text, salary text, overhead boolean)
language plpgsql stable security definer set search_path=public as $$
begin
  if not exists(select 1 from public.app_users
                where user_id=auth.uid() and active and role_keys && array['management']::text[]) then
    raise exception 'nur management';
  end if;
  return query
  select u.user_id, u.email,
    (public.perm_allowed_projects(u.user_id,'emp') is null
       and coalesce(public.perm(u.user_id,'emp')->>'salary','none')='all'
       and public.perm_overhead_ok(u.user_id))                             as is_full,
    coalesce(public.perm(u.user_id,'emp')->>'projects','own')              as projects,
    coalesce(public.perm(u.user_id,'emp')->'project_ids','[]'::jsonb)      as project_ids,
    coalesce(public.perm(u.user_id,'emp')->>'direction','down')           as direction,
    coalesce(public.perm(u.user_id,'emp')->>'salary','none')              as salary,
    public.perm_overhead_ok(u.user_id)                                     as overhead
  from public.app_users u
  where u.active and array_length(u.role_keys,1) is not null
    and not (u.role_keys && array['kunde']::text[]);
end $$;
revoke all on function public.ai_scope_overview() from public;
grant execute on function public.ai_scope_overview() to authenticated;
