-- Taxonomie-Zuschnitt, Punkt 1: Bereich „System" teilen. Neuer Bereich 'protokoll' (Protokoll & Aktivität):
-- NUR lesen. Empfänger = Management + Projektleiter (eigenes Team). Begründung (User 2026-08-30): das Protokoll
-- zeigt wer was wann getan hat, für die Beobachteten nicht neutral → nicht für jeden. activity_log + useractivity
-- wandern aus 'system' (Admin-Verwaltung, hartes Gate) hierher. 'system' behält Verwaltung + hartes Gate.

begin;

insert into public.permission_areas(key,label,seq,axes,menu_keys) values
  ('protokoll','Protokoll & Aktivität',14,
   '{"gehalt":false,"projekt":true,"hierarchie":false,"skill":false}'::jsonb,
   array['activity_log','useractivity']);

update public.permission_areas
  set menu_keys = array_remove(array_remove(menu_keys,'activity_log'),'useractivity')
  where key='system';

-- Seeds: Management sieht alles, Projektleiter das eigene Projekt-Team, hr/finance/teamlead nicht.
insert into public.role_permissions(role_key,area_key,visible,mode,salary,direction,projects,project_ids,skill) values
  ('management','protokoll',true,'read','none','side','all','{}'::text[],'all'),
  ('projektleiter','protokoll',true,'read','none','side','own','{}'::text[],'all'),
  ('finance','protokoll',false,'none','none','side','all','{}'::text[],'all'),
  ('hr','protokoll',false,'none','none','side','all','{}'::text[],'all'),
  ('teamlead','protokoll',false,'none','none','side','own','{}'::text[],'all');

-- activity_log Lesezugriff aufs Modell: mgmt alle; Projektleiter nur Handelnde aus dem eigenen Projekt
-- (user_id → employee → project); hr/finance raus (perm_mode='none'). INSERT-Policy bleibt (Logging).
drop policy if exists activity_read on public.activity_log;
create policy activity_read on public.activity_log for select to authenticated
using ( public.perm_mode(auth.uid(),'protokoll') <> 'none'
        and public.perm_proj_ok(auth.uid(),'protokoll',
             (select e.project_id from public.app_users au
                join public.employees e on e.id = au.employee_id
              where au.user_id = activity_log.user_id limit 1), null) );

-- Überblick-RPC: Management + Projektleiter (aufs eigene Team gescopet über perm_allowed_projects).
create or replace function public.management_activity_overview()
 returns table(user_id uuid, full_name text, role_keys text[], active boolean,
   last_sign_in timestamp with time zone, last_seen timestamp with time zone,
   last_activity_at timestamp with time zone, last_activity_kind text, last_activity_label text, edits_30d bigint)
 language plpgsql security definer set search_path to 'public'
as $function$
declare v_allowed text[];
begin
  if coalesce(public.perm_mode(auth.uid(),'protokoll'),'none') = 'none' then
    raise exception 'not authorized';
  end if;
  v_allowed := public.perm_allowed_projects(auth.uid(),'protokoll');   -- null = alle (Management)
  return query
  with sig as (
    select l.user_id as uid, l.created_at as at, l.entity as kind,
           coalesce(nullif(l.entity_label,''), l.entity) as label
    from public.activity_log l
    where l.action <> 'login' and l.user_id is not null
    union all
    select d.uploaded_by, d.created_at, 'upload'::text, coalesce(nullif(d.source_type,''), 'Datei')
    from public.data_imports d
    where d.uploaded_by is not null
  ),
  lastsig as ( select distinct on (uid) uid, at, kind, label from sig order by uid, at desc ),
  seenrows as (
    select uid, at from sig
    union all
    select l.user_id, l.created_at from public.activity_log l where l.action = 'login' and l.user_id is not null
  ),
  seen as ( select uid, max(at) as at from seenrows group by uid ),
  cnt as ( select uid, count(*) as n from sig where at > now() - interval '30 days' group by uid )
  select u.user_id, u.full_name, u.role_keys, u.active,
         au.last_sign_in_at,
         greatest(au.last_sign_in_at, sn.at) as last_seen,
         ls.at, ls.kind, ls.label, coalesce(c.n, 0)
  from public.app_users u
  left join auth.users au on au.id = u.user_id
  left join lastsig ls on ls.uid = u.user_id
  left join seen sn on sn.uid = u.user_id
  left join cnt c on c.uid = u.user_id
  where u.active is not false
    and u.role_keys && array['management','hr','finance','teamlead','projektleiter','qm','trainer','asp']::text[]
    and (v_allowed is null
         or exists(select 1 from public.employees e where e.id = u.employee_id and e.project_id = any(v_allowed)))
  order by ls.at asc nulls first;
end;
$function$;

commit;

-- ── ROLLBACK (manuell) ──
-- delete from public.role_permissions where area_key='protokoll';
-- update public.permission_areas set menu_keys = menu_keys || array['activity_log','useractivity'] where key='system';
-- delete from public.permission_areas where key='protokoll';
-- drop policy if exists activity_read on public.activity_log;
-- create policy activity_read on public.activity_log for select to authenticated
--   using (exists (select 1 from app_users u where u.user_id=auth.uid() and u.active and u.role_keys && array['management','hr','finance']::text[]));
-- (RPC: alte Fassung mit "if not is_management() then raise" wiederherstellen — siehe git.)
