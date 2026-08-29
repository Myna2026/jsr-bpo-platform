-- Vorhaben 3, Schnitt 3: Kern-Funktion OHNE Berechtigungs-Tor, damit agent-observe (service role, kein auth.uid)
-- die Vorschau rechnen kann. staffing_forecast (mit Tor) delegiert an sie. Nur service_role darf den Kern.
create or replace function public.staffing_forecast_core(p_project text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare d date := (now() at time zone 'Europe/Berlin')::date;
        cur_yw int := extract(isoyear from d)::int*100 + extract(week from d)::int;
        hi_yw int := cur_yw + 6;
begin
  return jsonb_build_object(
    'project', p_project,
    'project_name', (select name from public.projects where id=p_project),
    'has_forecast', exists(select 1 from public.report_forecast where project_id=p_project and fc_hours>0),
    'weeks', (
      with skills as (
        select lower(project_skill) as skill, round(avg(work_hours),1) as daily_h, count(*) as headcount
        from public.employees where project_id=p_project and status in ('active','training') and project_skill is not null
        group by lower(project_skill)
      ),
      fc as (
        select lower(skill) as skill, year*100+kw as yw, year, kw, sum(fc_hours) as req
        from public.report_forecast where project_id=p_project and (year*100+kw) between cur_yw and hi_yw and fc_hours>0
        group by lower(skill), year, kw
      ),
      pl as (
        select lower(skill) as skill, extract(isoyear from work_date)::int*100+extract(week from work_date)::int as yw,
          extract(isoyear from work_date)::int as year, extract(week from work_date)::int as kw,
          sum(coalesce(net_hours,0)) as planned, count(distinct employee_id) as planned_ma
        from public.shift_assignments where project_id=p_project and work_date > d and work_date <= d + 49
        group by lower(skill), extract(isoyear from work_date)::int, extract(week from work_date)::int
      ),
      cand as (
        select coalesce(fc.skill,pl.skill) as skill, coalesce(fc.yw,pl.yw) as yw,
          coalesce(fc.year,pl.year) as year, coalesce(fc.kw,pl.kw) as kw, fc.req, pl.planned, pl.planned_ma
        from fc full outer join pl on fc.skill=pl.skill and fc.yw=pl.yw
        where coalesce(fc.yw,pl.yw) > cur_yw
      )
      select coalesce(jsonb_agg(jsonb_build_object(
        'skill', c.skill, 'kw', c.kw, 'year', c.year,
        'required_h', round(c.req::numeric,1), 'planned_h', round(c.planned::numeric,1), 'planned_ma', c.planned_ma,
        'absent_ma', (
          select count(distinct e.id) from public.employees e, jsonb_array_elements(coalesce(e.absences,'[]'::jsonb)) a
          where e.project_id=p_project and lower(e.project_skill)=c.skill and (a->>'from') ~ '^\d{4}-\d{2}-\d{2}'
            and (a->>'from')::date <= to_date(c.year||'-'||c.kw,'IYYY-IW')+6
            and coalesce(nullif(a->>'to',''),(a->>'from'))::date >= to_date(c.year||'-'||c.kw,'IYYY-IW')),
        'status', case
            when c.req is null or c.planned is null then 'nicht_vorhersagbar'
            when c.req>0 and c.planned>0 and abs(c.req-c.planned)/greatest(c.req,c.planned) > 0.5 then 'skala_unklar'
            else 'ok' end,
        'scale_ratio', case when c.req>0 and c.planned>0 then round((c.planned/c.req)::numeric,2) else null end,
        'missing', (case when c.req is null then jsonb_build_array('Forecast') else '[]'::jsonb end)
                   || (case when c.planned is null then jsonb_build_array('Schichtplan') else '[]'::jsonb end),
        'gap_h', case when c.req is not null and c.planned is not null then round((c.req - c.planned)::numeric,1) else null end,
        'gap_people', case
            when c.req is not null and c.planned is not null and s.daily_h>0
                 and not (c.req>0 and c.planned>0 and abs(c.req-c.planned)/greatest(c.req,c.planned) > 0.5)
            then round(((c.req - c.planned)/(s.daily_h*5))::numeric) else null end
      ) order by c.kw, c.skill), '[]'::jsonb)
      from cand c left join skills s on s.skill=c.skill
    )
  );
end $$;
revoke all on function public.staffing_forecast_core(text) from public;
grant execute on function public.staffing_forecast_core(text) to service_role;

-- Tor-Version delegiert an den Kern.
create or replace function public.staffing_forecast(p_project text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not (public.is_management() or (public.is_planner() and p_project = public.get_my_employee_project_id())) then
    return jsonb_build_object('error','nicht berechtigt');
  end if;
  return public.staffing_forecast_core(p_project);
end $$;
grant execute on function public.staffing_forecast(text) to authenticated;
