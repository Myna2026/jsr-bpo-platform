-- Max überwacht auch den Schichtplan. Vier Prüfungen (mit Folge):
--  1) kein_plan            : für die kommende Woche steht noch kein Plan
--  2) unbesetzt            : Projekt/Skill hat Forecast-Bedarf, aber 0 geplante Stunden
--  3) abweichung_forecast  : geplante Stunden weichen deutlich (>25%) vom Forecast ab
--  4) eingeplant_abwesend  : jemand ist eingeplant, hat aber Urlaub/ist krank (WICHTIGSTER Punkt)
-- p_date = Bezugstag (Default heute, Berlin). Blick nach vorn. Service-role only.
create or replace function public.max_shift_scan(p_date date default null)
returns table(category text, subject text, detail text)
language plpgsql stable security definer set search_path=public as $$
declare d date := coalesce(p_date, (now() at time zone 'Europe/Berlin')::date);
        nyr int := extract(isoyear from d + 7)::int;
        nkw int := extract(week    from d + 7)::int;
begin
  return query
  -- 4) eingeplant trotz Abwesenheit (nächste 14 Tage) — der wichtigste Punkt
  select 'eingeplant_abwesend'::text, (e.first_name||' '||e.last_name),
    'ist am '||to_char(sa.work_date,'DD.MM.')||' eingeplant ('||coalesce((select name from public.projects where id=sa.project_id),'?')||'), '
      ||'hat aber '||(case when ab.t='sick' then 'sich krank gemeldet' when ab.t='vacation' then 'Urlaub' when ab.t='unpaid' then 'unbezahlt frei' else 'eine Abwesenheit' end)
      ||' — die Schicht bleibt unbesetzt, das fällt sonst erst auf, wenn niemand erscheint'
    from public.shift_assignments sa join public.employees e on e.id=sa.employee_id
    cross join lateral (
      select a->>'type' as t from jsonb_array_elements(coalesce(e.absences,'[]'::jsonb)) a
      where (a->>'from') ~ '^\d{4}-\d{2}-\d{2}' and (a->>'from')::date <= sa.work_date
        and coalesce(nullif(a->>'to',''),(a->>'from'))::date >= sa.work_date limit 1) ab
    where sa.work_date between d and d + 14
  union all
  -- 1) kommende Woche ungeplant (Projekt war zuletzt aktiv)
  select 'kein_plan', (select name from public.projects where id=ap.project_id),
    'für KW '||nkw||'/'||nyr||' steht noch kein Plan — die kommende Woche ist ungeplant, es kann niemand eingeteilt werden'
    from (select distinct project_id from public.shift_assignments where work_date >= d - 28) ap
    where not exists(select 1 from public.shift_assignments sa
      where sa.project_id=ap.project_id and extract(isoyear from sa.work_date)=nyr and extract(week from sa.work_date)=nkw)
  union all
  -- 2) unbesetzt trotz Bedarf: Forecast-Stunden vorhanden, aber 0 geplant (kommende Woche)
  select 'unbesetzt', (select name from public.projects where id=rf.project_id)||' · '||rf.skill,
    'Forecast fordert '||round(rf.fc_hours)||' h für KW '||nkw||', geplant sind aber 0 — der Bedarf ist unbesetzt'
    from public.report_forecast rf
    where rf.year=nyr and rf.kw=nkw and rf.fc_hours>0
      and coalesce((select sum(sa.net_hours) from public.shift_assignments sa
        where sa.project_id=rf.project_id and sa.skill=rf.skill and extract(isoyear from sa.work_date)=nyr and extract(week from sa.work_date)=nkw),0) = 0
  union all
  -- 3) geplante Stunden weichen deutlich vom Forecast ab (>25%, geplant>0)
  select 'abweichung_forecast', (select name from public.projects where id=rf.project_id)||' · '||rf.skill,
    'geplant '||round(pl.planned)||' h vs Forecast '||round(rf.fc_hours)||' h für KW '||nkw
      ||' ('||(case when pl.planned>rf.fc_hours then '+' else '' end)||round((pl.planned-rf.fc_hours)/rf.fc_hours*100)||'%)'
      ||' — '||(case when pl.planned>rf.fc_hours then 'überplant, Kosten höher als nötig' else 'unterplant, Bedarf womöglich nicht gedeckt' end)
    from public.report_forecast rf
    cross join lateral (select coalesce(sum(sa.net_hours),0) as planned from public.shift_assignments sa
      where sa.project_id=rf.project_id and sa.skill=rf.skill and extract(isoyear from sa.work_date)=nyr and extract(week from sa.work_date)=nkw) pl
    where rf.year=nyr and rf.kw=nkw and rf.fc_hours>0 and pl.planned>0 and abs(pl.planned-rf.fc_hours)/rf.fc_hours > 0.25;
end $$;
grant execute on function public.max_shift_scan(date) to service_role;
