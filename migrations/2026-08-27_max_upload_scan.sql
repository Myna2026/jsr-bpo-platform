-- Max überwacht die Uploads aktiv (nicht nur die Ampel) und meldet mit Kontext. Vier Typen:
--  1) ueberfaellig   : eine fällige Quelle fehlt (Wochenende+grace vorbei), inkl. „seit N Wochen" + Folge (was leer bleibt)
--  2) unvollstaendig : eine fällige Woche ist angefangen, aber eine Quelle fehlt noch
--  3) wenig_zeilen   : eine Datei kam, aber mit auffallend wenigen Zeilen (< 40% des Quellen-Schnitts)
--  4) muster         : dieselbe Quelle bleibt regelmäßig liegen (≥3 der letzten 6 fälligen Wochen)
-- Deterministisch aus upload_schedule + data_imports + projects. Service-role only.
create or replace function public.max_upload_scan()
returns table(category text, subject text, detail text)
language plpgsql stable security definer set search_path=public as $$
declare today date := (now() at time zone 'Europe/Berlin')::date;
begin
  return query
  with sched as (
    select us.project_id, us.source_type, coalesce(us.cadence,'weekly_progressive') as cadence, coalesce(us.grace_days,1) as grace
    from public.upload_schedule us where coalesce(us.active,true)
  ),
  pname as (select id, name from public.projects),
  cons as (select * from (values
      ('calls','die Anruf-Mengen'),('calls_inbound','die AHT und ACW'),('gauges','die CSAT-Werte'),
      ('rohdaten','die Arbeitsstunden'),('booking_a','die Buchungs-KPIs'),('booking_week','die Wochen-Buchungen'),
      ('booking_month','die Monats-Buchungen'),('forecast_sales','der Sales-Forecast'),('forecast_support','der Support-Forecast'),
      ('longterm','die Langzeit-Kennzahlen')
    ) c(src, folge)),
  slabel as (select * from (values
      ('calls','Call-CSV gesamt'),('calls_inbound','Call-CSV Inbound'),('gauges','Gauges'),('rohdaten','Rohdaten-Stunden'),
      ('booking_a','Booking je Agent'),('booking_week','Booking Woche'),('booking_month','Booking Monat'),
      ('forecast_sales','Forecast Sales'),('forecast_support','Forecast Support'),('longterm','Langzeit')
    ) c(src, lbl)),
  weeks as (
    select extract(isoyear from gs)::int as yr, extract(week from gs)::int as kw, (gs::date + 6) as wk_sunday
    from generate_series(date_trunc('week', today) - interval '5 weeks', date_trunc('week', today), interval '1 week') gs
  ),
  due_weekly as (   -- fällige Wochen je weekly-Quelle (Wochenende + grace vor heute)
    select s.project_id, s.source_type, w.yr, w.kw, w.wk_sunday
    from sched s cross join weeks w
    where s.cadence like 'weekly%' and (w.wk_sunday + (s.grace||' days')::interval) < today
  ),
  miss as (         -- fällig, aber kein Import
    select d.* from due_weekly d
    where not exists(select 1 from public.data_imports di
      where di.project_id=d.project_id and di.source_type=d.source_type and di.kw=d.kw and di.year=d.yr)
  ),
  latest_due as (   -- jüngste fällige Woche je Quelle
    select project_id, source_type, max(kw + yr*100) as maxkey from due_weekly group by 1,2
  )
  -- 1) ueberfaellig: jüngste fällige Woche fehlt; „seit N Wochen" = Anzahl fehlender fälliger Wochen
  select 'ueberfaellig'::text,
         (select name from pname where id=m.project_id)||' · '||coalesce((select lbl from slabel where src=m.source_type),m.source_type),
         'fehlt seit '||(select count(*) from miss m2 where m2.project_id=m.project_id and m2.source_type=m.source_type)::text
           ||' Woche(n) (zuletzt KW '||m.kw||'/'||m.yr||')'
           ||coalesce(', dadurch bleibt '||(select folge from cons where src=m.source_type)||' leer','')
    from miss m join latest_due ld on ld.project_id=m.project_id and ld.source_type=m.source_type and (m.kw+m.yr*100)=ld.maxkey
  union all
  -- 2) unvollstaendig: eine fällige Woche, in der DIESE Quelle fehlt, aber eine ANDERE derselben Woche/Projekt schon da ist
  select 'unvollstaendig',
         (select name from pname where id=m.project_id)||' · KW '||m.kw||'/'||m.yr,
         coalesce((select lbl from slabel where src=m.source_type),m.source_type)||' fehlt noch'
    from miss m
    where exists(select 1 from public.data_imports di where di.project_id=m.project_id and di.kw=m.kw and di.year=m.yr)
      and not exists(select 1 from latest_due ld where ld.project_id=m.project_id and ld.source_type=m.source_type and (m.kw+m.yr*100)=ld.maxkey)
  union all
  -- 3) wenig_zeilen: Import mit auffallend wenigen Zeilen (< 40% des Schnitts der übrigen Importe dieser Quelle/Projekt)
  select 'wenig_zeilen',
         (select name from pname where id=di.project_id)||' · '||coalesce((select lbl from slabel where src=di.source_type),di.source_type)||' KW '||di.kw||'/'||di.year,
         di.row_count||' Zeilen statt üblich ~'||round(av.avg_rows)::text
    from public.data_imports di
    join lateral (select avg(row_count) as avg_rows, count(*) as n from public.data_imports d2
                  where d2.project_id=di.project_id and d2.source_type=di.source_type and d2.id<>di.id) av on true
    where di.created_at > today - interval '6 weeks' and av.n>=2 and di.row_count is not null and av.avg_rows>0
      and di.row_count < av.avg_rows*0.4
  union all
  -- 4) muster: Quelle in ≥3 der letzten fälligen Wochen liegen geblieben
  select 'muster',
         (select name from pname where id=m.project_id)||' · '||coalesce((select lbl from slabel where src=m.source_type),m.source_type),
         'bleibt regelmäßig liegen ('||count(*)::text||' von '||(select count(*) from weeks)::text||' Wochen fehlend)'
    from miss m group by m.project_id, m.source_type having count(*)>=3;
end $$;
grant execute on function public.max_upload_scan() to service_role;
