-- Anmelde- und Aktivitaetsuebersicht (Management-only). Fasst je App-User zusammen:
-- letzte Anmeldung (auth.users.last_sign_in_at), letzte echte Aktivitaet (activity_log ohne login
-- + Uploads aus data_imports) mit Art/Bezeichnung, sowie Zahl der Eintraege der letzten 30 Tage.
-- SECURITY DEFINER: liest auth.users + bypassed RLS, aber hart auf is_management() gegated.
drop function if exists public.management_activity_overview();
create or replace function public.management_activity_overview()
returns table(
  user_id uuid,
  full_name text,
  role_keys text[],
  active boolean,
  last_sign_in timestamptz,
  last_seen timestamptz,
  last_activity_at timestamptz,
  last_activity_kind text,
  last_activity_label text,
  edits_30d bigint
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_management() then
    raise exception 'not authorized';
  end if;
  return query
  with sig as (
    select l.user_id as uid, l.created_at as at,
           l.entity as kind,
           coalesce(nullif(l.entity_label,''), l.entity) as label
    from public.activity_log l
    where l.action <> 'login' and l.user_id is not null
    union all
    select d.uploaded_by, d.created_at, 'upload'::text,
           coalesce(nullif(d.source_type,''), 'Datei')
    from public.data_imports d
    where d.uploaded_by is not null
  ),
  lastsig as (
    select distinct on (uid) uid, at, kind, label
    from sig
    order by uid, at desc
  ),
  -- "Zuletzt gesehen": jedes Praesenz-Signal = Datenpflege/Uploads (sig) PLUS die login-Zeilen.
  -- Nur so wird eine laufende Sitzung sichtbar, deren last_sign_in_at veraltet ist.
  seenrows as (
    select uid, at from sig
    union all
    select l.user_id, l.created_at from public.activity_log l where l.action = 'login' and l.user_id is not null
  ),
  seen as (
    select uid, max(at) as at from seenrows group by uid
  ),
  cnt as (
    select uid, count(*) as n
    from sig
    where at > now() - interval '30 days'
    group by uid
  )
  select u.user_id, u.full_name, u.role_keys, u.active,
         au.last_sign_in_at,
         greatest(au.last_sign_in_at, sn.at) as last_seen,
         ls.at, ls.kind, ls.label,
         coalesce(c.n, 0)
  from public.app_users u
  left join auth.users au on au.id = u.user_id
  left join lastsig ls on ls.uid = u.user_id
  left join seen sn on sn.uid = u.user_id
  left join cnt c on c.uid = u.user_id
  where u.active is not false
    -- nur Back-Office-Zugaenge (HR-Portal), die tatsaechlich Daten pflegen;
    -- reine Mitarbeiter (eigenes Portal) und Kunden bleiben aussen vor.
    and u.role_keys && array['management','hr','finance','teamlead','projektleiter','qm','trainer','asp']::text[]
  order by ls.at asc nulls first;
end;
$$;

grant execute on function public.management_activity_overview() to authenticated;
