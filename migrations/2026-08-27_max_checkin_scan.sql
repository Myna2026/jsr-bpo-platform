-- Max überwacht auch den Check-in. Drei Prüfungen (mit Folge, für Max' Stimme):
--  1) nicht_eingecheckt: wer für den Tag in der Schicht steht, aber nicht eingecheckt hat (nicht krank/abwesend)
--  2) kein_checkout    : wer regelmäßig vergisst auszuchecken (arrival gesetzt, departure leer, ≥3× in 14 Tagen)
--  3) unbestaetigt     : abgeschlossene Check-ins, die der Teamleiter seit ≥2 Tagen nicht bestätigt hat
-- p_date = zu prüfender Tag (Default: gestern, Berlin). Service-role only.
create or replace function public.max_checkin_scan(p_date date default null)
returns table(category text, subject text, detail text)
language plpgsql stable security definer set search_path=public as $$
declare d date := coalesce(p_date, ((now() at time zone 'Europe/Berlin')::date - 1));
begin
  return query
  with sched as (
    select distinct sa.project_id, sa.employee_id from public.shift_assignments sa
    where sa.work_date = d and sa.employee_id is not null
  ),
  ok as (select employee_id from public.shift_checkins where work_date = d and status in ('present','sick')),
  absent as (
    select e.id from public.employees e where exists(
      select 1 from jsonb_array_elements(coalesce(e.absences,'[]'::jsonb)) a
      where (a->>'from') ~ '^\d{4}-\d{2}-\d{2}'
        and (a->>'from')::date <= d
        and coalesce(nullif(a->>'to',''),(a->>'from'))::date >= d)
  ),
  missing as (
    select s.project_id, s.employee_id from sched s
    where s.employee_id not in (select employee_id from ok)
      and s.employee_id not in (select id from absent)
  )
  -- 1) geplant, aber nicht eingecheckt (je Projekt gebündelt, mit Namen)
  select 'nicht_eingecheckt'::text,
    (select name from public.projects where id=m.project_id)||' · '||to_char(d,'DD.MM.'),
    count(*)::text||' geplante ohne Check-in ('||string_agg((e.first_name||' '||e.last_name), ', ' order by e.first_name)
      ||') — dadurch fehlen ihre Stunden und die Anwesenheit ist unklar'
    from missing m join public.employees e on e.id=m.employee_id group by m.project_id
  union all
  -- 2) vergisst regelmäßig auszuchecken
  select 'kein_checkout', (e.first_name||' '||e.last_name),
    'vergisst regelmäßig auszuchecken ('||count(*)::text||'× in 14 Tagen) — die Arbeitszeit bleibt unvollständig'
    from public.shift_checkins sc join public.employees e on e.id=sc.employee_id
    where sc.status='present' and sc.arrival is not null and sc.departure is null and sc.work_date >= d-14
    group by sc.employee_id, e.first_name, e.last_name having count(*) >= 3
  union all
  -- 3) Teamleiter bestätigt die abgeschlossenen Check-ins seit ≥2 Tagen nicht
  select 'unbestaetigt', coalesce((select name from public.projects where id=sc.project_id), sc.project_id),
    count(*)::text||' Check-ins seit ≥2 Tagen unbestätigt — der Teamleiter hat die Anwesenheit nicht freigegeben'
    from public.shift_checkins sc
    where sc.status='present' and sc.departure is not null and sc.confirmed_at is null
      and sc.work_date <= d-2 and sc.work_date >= d-21
    group by sc.project_id having count(*) >= 1;
end $$;
grant execute on function public.max_checkin_scan(date) to service_role;
