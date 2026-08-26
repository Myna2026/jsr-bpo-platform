-- Detail/Historie je Person für „Nutzung & Aktivität" (Management-only). Ein Aufruf pro Klick liefert alles
-- serverseitig verdichtet: Wochen-Verlauf, Sitzungen, besuchte Bereiche, Änderungen, Tagesaufgaben (erledigt/
-- verschoben/leer abgehakt), Mayas Sätze der letzten Tage, plus errechnete Auffälligkeiten.
create or replace function public.usage_user_detail(p_user uuid, p_days int default 42)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  d_from date := current_date - (greatest(p_days,7) - 1);
  v_daily jsonb; v_sessions jsonb; v_areas jsonb; v_changes jsonb; v_digests jsonb;
  last_active timestamptz; act7 int; act_prev int; empty_tasks int; done_tasks int; snoozed int;
  anom text[] := '{}';
begin
  if auth.uid() is not null and not public.is_management() then raise exception 'not authorized'; end if;

  with days as (select generate_series(d_from, current_date, interval '1 day')::date dd),
  se as (select started_at::date d, count(*) n, round(sum(greatest(0, extract(epoch from (last_seen-started_at))/60)))::int mins
         from public.user_sessions where user_id=p_user and started_at::date between d_from and current_date group by 1),
  al as (select created_at::date d, action, entity from public.activity_log where user_id=p_user and created_at::date between d_from and current_date),
  wr as (select d, count(*) n from al where action in ('create','update','delete') group by d),
  vw as (select d, count(*) n from al where action='view' group by d),
  ta as (select done_at::date d, count(*) n, count(*) filter (where session_writes=0) e
         from public.daily_tasks_done where done_by=p_user and done_at::date between d_from and current_date group by 1)
  select jsonb_agg(jsonb_build_object('day',dd,'sessions',coalesce(se.n,0),'minutes',coalesce(se.mins,0),
           'writes',coalesce(wr.n,0),'views',coalesce(vw.n,0),'tasks_done',coalesce(ta.n,0),'tasks_empty',coalesce(ta.e,0)) order by dd)
    into v_daily from days
    left join se on se.d=days.dd left join wr on wr.d=days.dd left join vw on vw.d=days.dd left join ta on ta.d=days.dd;

  select jsonb_agg(jsonb_build_object('started_at',started_at,'last_seen',last_seen,
           'minutes',round(greatest(0, extract(epoch from (last_seen-started_at))/60))::int,'pings',ping_count) order by started_at desc)
    into v_sessions from (select * from public.user_sessions where user_id=p_user order by started_at desc limit 25) s;

  select jsonb_agg(jsonb_build_object('area',entity,'count',n) order by n desc)
    into v_areas from (select entity, count(*) n from public.activity_log
      where user_id=p_user and action='view' and entity is not null and created_at::date>=d_from group by entity) x;

  select jsonb_agg(jsonb_build_object('entity',entity,'count',n) order by n desc)
    into v_changes from (select coalesce(entity,'-') entity, count(*) n from public.activity_log
      where user_id=p_user and action in ('create','update','delete') and created_at::date>=d_from group by 1) x;

  select count(*), count(*) filter (where session_writes=0) into done_tasks, empty_tasks
    from public.daily_tasks_done where done_by=p_user and done_at::date>=d_from;
  select count(*) into snoozed from public.task_snooze where user_id=p_user and date>=d_from;

  select jsonb_agg(jsonb_build_object('day',day,'summary',summary) order by day desc)
    into v_digests from (select day, summary from public.usage_digests where user_id=p_user and day>=d_from order by day desc limit p_days) x;

  -- Auffälligkeiten
  select greatest(coalesce(max(created_at),'epoch'::timestamptz),
                  coalesce((select max(last_seen) from public.user_sessions where user_id=p_user),'epoch'::timestamptz))
    into last_active from public.activity_log where user_id=p_user;
  if coalesce(empty_tasks,0) >= 3 and coalesce(empty_tasks,0) >= 0.5*greatest(coalesce(done_tasks,0),1) then
    anom := anom || 'dauerhaft leere Häkchen'; end if;
  if last_active is null or last_active < now()-interval '7 days' then
    anom := anom || ('länger nicht aktiv'||case when last_active > 'epoch'::timestamptz then ' (seit '||extract(day from now()-last_active)::int||' Tagen)' else '' end);
  end if;
  select count(distinct created_at::date) into act7 from public.activity_log where user_id=p_user and created_at>=now()-interval '7 days';
  select count(distinct created_at::date) into act_prev from public.activity_log where user_id=p_user and created_at>=now()-interval '28 days' and created_at<now()-interval '7 days';
  if coalesce(act_prev,0) >= 8 and coalesce(act7,0) = 0 then anom := anom || 'Aktivität plötzlich abgebrochen'; end if;

  return jsonb_build_object(
    'daily', coalesce(v_daily,'[]'::jsonb), 'sessions', coalesce(v_sessions,'[]'::jsonb),
    'areas', coalesce(v_areas,'[]'::jsonb), 'changes', coalesce(v_changes,'[]'::jsonb),
    'tasks', jsonb_build_object('done',coalesce(done_tasks,0),'empty',coalesce(empty_tasks,0),'snoozed',coalesce(snoozed,0)),
    'digests', coalesce(v_digests,'[]'::jsonb), 'anomalies', to_jsonb(anom),
    'last_active', last_active);
end $$;
revoke all    on function public.usage_user_detail(uuid, int) from public;
grant execute on function public.usage_user_detail(uuid, int) to authenticated;
