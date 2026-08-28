-- v3: weak/strong tragen zusätzlich band (Ampel-Farbe in der Mail) und emp_id (Deep-Link je Name
--     -> hr.html?goto=emp&id=…). Rest identisch zu v2.
create or replace function public.leader_situations()
returns table(project_id text, skill text, project_name text, leaders jsonb, situation jsonb)
language plpgsql stable security definer set search_path=public as $$
declare d date := (now() at time zone 'Europe/Berlin')::date;
        wk_start date := date_trunc('week', d)::date;
        cur_yw int := extract(isoyear from d)::int*100 + extract(week from d)::int;
begin
  return query
  with grp as (
    select e.project_id, lower(e.project_skill) as skill
    from public.employees e
    where e.position='Teamleiter' and e.project_skill is not null and e.status in ('active','training')
    group by e.project_id, lower(e.project_skill)
  ),
  team as (
    select g.project_id, g.skill, e.id as emp_id, (e.first_name||' '||e.last_name) as name, e.contract, e.absences
    from grp g join public.employees e on e.project_id=g.project_id and lower(e.project_skill)=g.skill
      and e.position in ('Agent','Senior Agent','ASP') and e.status in ('active','training')
  ),
  leaders as (
    select g.project_id, g.skill,
      jsonb_agg(jsonb_build_object('name', e.first_name||' '||e.last_name, 'user_id', au.user_id)) as leaders
    from grp g join public.employees e on e.project_id=g.project_id and lower(e.project_skill)=g.skill
      and e.position='Teamleiter' and e.status in ('active','training')
    left join public.app_users au on au.employee_id=e.id
    group by g.project_id, g.skill
  ),
  kw_pick as (
    select t.project_id, t.skill, max(ke.year*100+ke.kw) as yw
    from team t join public.kpi_entries ke on ke.emp_id=t.emp_id
    where (ke.year*100+ke.kw) <= cur_yw
    group by t.project_id, t.skill
  ),
  vals as (
    select t.project_id, t.skill, t.name, t.emp_id, kc.name as kpi, kc.id as kpi_id, ke.value, kp.yw,
      (select b->>'label' from jsonb_array_elements(kc.thresholds) b
        where ke.value >= (b->>'min')::numeric and ke.value <= (b->>'max')::numeric limit 1) as band,
      (select round(avg(ke2.value),2) from public.kpi_entries ke2
         join team t2 on t2.emp_id=ke2.emp_id and t2.project_id=t.project_id and t2.skill=t.skill
         where ke2.kpi_id=kc.id and ke2.year*100+ke2.kw = kp.yw) as team_avg,
      (select round(ke3.value,2) from public.kpi_entries ke3
         where ke3.emp_id=t.emp_id and ke3.kpi_id=kc.id and ke3.year*100+ke3.kw = kp.yw-1 limit 1) as prev,
      case when (t.contract->>'start') ~ '^\d{4}-\d{2}-\d{2}' then round((d-(t.contract->>'start')::date)/7.0)::int end as tenure_weeks,
      (select (d - max(fs.conducted_at)::date) from public.feedback_sessions fs where fs.employee_id=t.emp_id and fs.conducted_at is not null) as last_fb_days,
      (select round(wc.avg_acw_sec)    from public.weekly_calls wc where wc.employee_id=t.emp_id and wc.year*100+wc.kw=kp.yw limit 1) as acw_sec,
      (select round(wc.avg_handle_sec) from public.weekly_calls wc where wc.employee_id=t.emp_id and wc.year*100+wc.kw=kp.yw limit 1) as aht_sec,
      (select round(wc.avg_hold_sec)   from public.weekly_calls wc where wc.employee_id=t.emp_id and wc.year*100+wc.kw=kp.yw limit 1) as hold_sec
    from team t
    join public.kpi_entries ke on ke.emp_id=t.emp_id
    join public.kpi_config kc on kc.id=ke.kpi_id and lower(kc.skill)=t.skill
    join kw_pick kp on kp.project_id=t.project_id and kp.skill=t.skill and (ke.year*100+ke.kw)=kp.yw
  ),
  weak as (select v.project_id, v.skill, jsonb_agg(jsonb_build_object(
      'name',v.name,'emp_id',v.emp_id,'kpi',v.kpi,'band',v.band,'value',round(v.value,2),'prev',v.prev,'team_avg',v.team_avg,
      'tenure_weeks',v.tenure_weeks,'last_fb_days',v.last_fb_days,'acw_sec',v.acw_sec,'aht_sec',v.aht_sec,'hold_sec',v.hold_sec)) as arr
    from vals v where v.band in ('Kritisch','Schlecht') group by v.project_id, v.skill),
  strong as (select v.project_id, v.skill, jsonb_agg(jsonb_build_object('name',v.name,'emp_id',v.emp_id,'kpi',v.kpi,'band',v.band,'value',round(v.value,2))) as arr
    from vals v where v.band='Sehr gut' group by v.project_id, v.skill),
  absent as (select t.project_id, t.skill, jsonb_agg(distinct jsonb_build_object('name',t.name,'type',a->>'type')) as arr
    from team t, jsonb_array_elements(coalesce(t.absences,'[]'::jsonb)) a
    where (a->>'from') ~ '^\d{4}-\d{2}-\d{2}' and (a->>'from')::date <= wk_start+6
      and coalesce(nullif(a->>'to',''),(a->>'from'))::date >= wk_start
    group by t.project_id, t.skill),
  newj as (select tm.project_id, tm.skill, jsonb_agg(tm.name) as arr from team tm
    where (tm.contract->>'start') ~ '^\d{4}-\d{2}-\d{2}' and (tm.contract->>'start')::date > d-28 group by tm.project_id, tm.skill),
  nofb as (select t.project_id, t.skill, jsonb_agg(t.name) as arr from team t
    where (t.contract->>'start') ~ '^\d{4}-\d{2}-\d{2}' and (t.contract->>'start')::date <= d-28
      and not exists(select 1 from public.feedback_sessions fs where fs.employee_id=t.emp_id and fs.conducted_at is not null)
    group by t.project_id, t.skill),
  sizes as (select tm.project_id, tm.skill, count(*) as n from team tm group by tm.project_id, tm.skill)
  select g.project_id, g.skill, (select name from public.projects where id=g.project_id),
    l.leaders,
    jsonb_build_object(
      'team_size', coalesce(s.n,0),
      'absent', coalesce(ab.arr,'[]'::jsonb),
      'weak', coalesce(w.arr,'[]'::jsonb),
      'strong', coalesce(st.arr,'[]'::jsonb),
      'new_joiners', coalesce(nj.arr,'[]'::jsonb),
      'no_feedback', coalesce(nf.arr,'[]'::jsonb)
    )
  from grp g
  join leaders l on l.project_id=g.project_id and l.skill=g.skill
  left join sizes s on s.project_id=g.project_id and s.skill=g.skill
  left join absent ab on ab.project_id=g.project_id and ab.skill=g.skill
  left join weak w on w.project_id=g.project_id and w.skill=g.skill
  left join strong st on st.project_id=g.project_id and st.skill=g.skill
  left join newj nj on nj.project_id=g.project_id and nj.skill=g.skill
  left join nofb nf on nf.project_id=g.project_id and nf.skill=g.skill;
end $$;
grant execute on function public.leader_situations() to service_role;
