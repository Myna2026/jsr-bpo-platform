-- Maya prüft täglich auch die Zugriffsrechte und meldet Auffälligkeiten (nüchtern, ohne Wertung). Vier Typen:
--  1) verwaiste Sperren/Freigaben (Punkt existiert nicht mehr, oder Zugang gelöscht) -> laufen ins Leere
--  2) Rechte, die zur Rolle nicht passen (Freigabe eines Kosten-/Verwaltungspunkts an eine Rolle ohne diesen Anspruch)
--  3) ungenutzte Zugänge mit weitreichenden Rechten (management/hr/finance, lange/nie angemeldet)
--  4) Widersprüche Menü <-> KI-Datenrechte bei Löhnen (sieht Löhne im Menü, darf sie per KI nicht abfragen; umgekehrt)
-- Deterministisch aus app_config (Sperren/Freigaben), app_users, auth.users, ai_effective_prefs. Service-role only.
create or replace function public.maya_access_scan()
returns table(category text, subject text, detail text)
language plpgsql stable security definer set search_path=public as $$
declare
  valid text[] := array['start','daily_tasks','calendar','meetingnotes','agents','cockpit','wissen_system','nlquery',
    'datacheck','shiftplan','checkin','timetracking','absences','urlaubantraege','workforce','employees','orgchart',
    'performance','payroll','kanban','funnel','cvs','onboarding','bewerberlinks','dubletten','recmkt','feedback',
    'auswertung','callqa','projects','praesentation','uploads','dataimport','uploadplan','cvsync','forecast','fcist',
    'profitability','productivity','locations','spaces','training_plans','timeline','showcase','skillmatrix','elearning',
    'knowledge','languagetest','test_editor','test_preview','superadmin','cockpits','appusers','aiaccess','whosees',
    'hraccess','tabperms','activity_log','useractivity','taskadmin','mein-plan'];
  cost   text[] := array['profitability','productivity','locations','payroll'];
  adminb text[] := array['superadmin','appusers','hraccess','tabperms','aiaccess','whosees','useractivity','taskadmin'];
  locks  jsonb; grants jsonb;
begin
  select value into locks  from public.app_config where key='jsr_hr_tab_locks_v1';
  select value into grants from public.app_config where key='jsr_menu_grants_v1';
  locks  := coalesce(locks,'{}'::jsonb);
  grants := coalesce(grants,'{}'::jsonb);

  return query
  with lk as (select k as uid, v from jsonb_each(locks)  as t(k,v)),
       gr as (select k as uid, v from jsonb_each(grants) as t(k,v)),
       lk_keys as (select uid, e as key from lk, jsonb_array_elements_text(v) as e),
       gr_keys as (select uid, e as key from gr, jsonb_array_elements_text(v) as e),
       usr as (
         select a.user_id::text as uid, coalesce(u.email::text, a.full_name, a.user_id::text) as nm,
                coalesce(a.role_keys,'{}') as role_keys, coalesce(a.active,true) as active,
                greatest(
                  u.last_sign_in_at,
                  (select max(created_at) from public.activity_log  al where al.user_id = a.user_id),
                  (select max(last_seen)  from public.user_sessions se where se.user_id = a.user_id)
                ) as last_active
         from public.app_users a left join auth.users u on u.id=a.user_id
       ),
       sal as (
         select us.uid, us.nm,
           ( (us.role_keys && array['management','finance'])
             or ( exists(select 1 from gr_keys g where g.uid=us.uid and g.key='payroll')
                  and not exists(select 1 from lk_keys l where l.uid=us.uid and l.key='payroll') ) ) as menu_salary,
           coalesce((public.ai_effective_prefs(us.uid::uuid)->>'salaries') <> 'none', false) as ai_salary
         from usr us where us.active
       )
  -- 1) verwaist: Sperre/Freigabe auf nicht mehr existierenden Menüpunkt
  select 'verwaist'::text, coalesce(us.nm, l.uid), 'Sperre auf unbekannten Punkt „'||l.key||'"'
    from lk_keys l left join usr us on us.uid=l.uid where l.key <> all(valid)
  union all
  select 'verwaist', coalesce(us.nm, g.uid), 'Freigabe auf unbekannten Punkt „'||g.key||'"'
    from gr_keys g left join usr us on us.uid=g.uid where g.key <> all(valid)
  union all
  -- verwaist: Einstellungen für einen gelöschten Zugang
  select 'verwaist', d.uid, 'Menü-Einstellungen für einen nicht mehr vorhandenen Zugang'
    from (select uid from lk union select uid from gr) d
    where not exists(select 1 from usr us where us.uid=d.uid)
  union all
  -- 2) Rolle passt nicht: Kostenbereich freigegeben trotz Rolle ohne Kostenanspruch
  select 'rolle', us.nm, 'Freigabe Kostenbereich „'||g.key||'" trotz Rolle '||array_to_string(us.role_keys,'/')
    from gr_keys g join usr us on us.uid=g.uid
    where g.key = any(cost) and not (us.role_keys && array['management','finance'])
  union all
  select 'rolle', us.nm, 'Freigabe Verwaltung „'||g.key||'" trotz Rolle '||array_to_string(us.role_keys,'/')
    from gr_keys g join usr us on us.uid=g.uid
    where g.key = any(adminb) and not (us.role_keys && array['management','hr'])
  union all
  -- 3) ungenutzt + weitreichend
  select 'ungenutzt', us.nm, 'weitreichende Rechte ('||array_to_string(us.role_keys,'/')||'), zuletzt aktiv '||coalesce(to_char(us.last_active,'YYYY-MM-DD'),'nie')
    from usr us
    where us.active and (us.role_keys && array['management','hr','finance'])
      and (us.last_active is null or us.last_active < now() - interval '60 days')
  union all
  -- 4) Widerspruch Menü <-> KI (Löhne)
  select 'widerspruch', nm, 'sieht Löhne im Menü, darf sie per KI aber nicht abfragen' from sal where menu_salary and not ai_salary
  union all
  select 'widerspruch', nm, 'darf Löhne per KI abfragen, sieht sie im Menü aber nicht' from sal where ai_salary and not menu_salary;
end $$;
grant execute on function public.maya_access_scan() to service_role;
