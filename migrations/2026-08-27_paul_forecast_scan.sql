-- Paul überwacht Forecast gegen Ist (gelieferte Stunden). Je Projekt UND Skill getrennt.
-- Ist = Σ weekly_hours.hours, Forecast = report_forecast.fc_hours — dieselbe Rechnung wie das
-- Cockpit „Forecast vs. Ist". Fenster: 8 abgeschlossene Wochen (laufende Woche unvollständig -> raus).
-- Abweichung dev = (Ist − FC)/FC:  negativ = Unterdeckung (wir liefern zu wenig), positiv = Überdeckung.
--
-- Schwellen (mit dem User abgestimmt):
--   einmalig (jüngste Woche):  |dev| >= 15 %
--   anhaltend (Trend):         >= 3 der letzten 4 Wochen gleiche Richtung, je |dev| >= 10 %
-- Trend hat Vorrang; die Einmal-Meldung entfällt, wenn ein Trend gleicher Richtung läuft.
--
-- Paul spricht mit Konfidenz: sehr große Abweichungen (>= 80 %) sind eher unterschiedliche Messung
-- als echte Lücke (Konfidenz niedrig), dünne Datenbasis senkt die Konfidenz, sonst belastbar.
create or replace function public.paul_forecast_scan(p_date date default null)
returns table(category text, subject text, detail text)
language plpgsql stable security definer set search_path=public as $$
declare d date := coalesce(p_date, (now() at time zone 'Europe/Berlin')::date);
begin
  return query
  with wk as (
    select gs::date as monday, extract(isoyear from gs)::int as yr, extract(week from gs)::int as kw,
           row_number() over (order by gs) as pos    -- 1=ältest … 8=jüngst
    from generate_series(date_trunc('week', d) - interval '8 weeks', date_trunc('week', d) - interval '1 week', interval '1 week') gs
  ),
  fc as (select rf.project_id, lower(rf.skill) as skill, rf.year, rf.kw, sum(rf.fc_hours) as fc
          from public.report_forecast rf group by 1,2,3,4),
  ist as (select wh.project_id, lower(wh.skill) as skill, wh.year, wh.kw, sum(wh.hours) as ist
          from public.weekly_hours wh group by 1,2,3,4),
  cmp as (
    select f.project_id, f.skill, w.kw, w.pos, f.fc, i.ist,
           case when f.fc>0 and i.ist is not null then (i.ist - f.fc)/f.fc*100 end as dev
    from wk w join fc f on f.year=w.yr and f.kw=w.kw
    left join ist i on i.project_id=f.project_id and i.skill=f.skill and i.year=w.yr and i.kw=w.kw
    where f.fc>0
  ),
  agg as (
    select project_id, skill,
      count(*) filter (where dev is not null) as n_data,
      count(*) filter (where pos>=5 and dev is not null) as n_recent,
      count(*) filter (where pos>=5 and dev <= -10) as n_unter,
      count(*) filter (where pos>=5 and dev >=  10) as n_ueber,
      avg(dev) filter (where pos>=5 and dev <= -10) as avg_unter,
      avg(dev) filter (where pos>=5 and dev >=  10) as avg_ueber
    from cmp group by project_id, skill
  ),
  latest as (
    select distinct on (project_id, skill) project_id, skill, kw, fc, ist, dev
    from cmp where dev is not null order by project_id, skill, pos desc
  ),
  pn as (select id, name from public.projects)
  -- 1) Trend Unterdeckung (>=3 der letzten 4 Wochen, je >=10% unter Plan)
  select 'fc_unterdeckung_trend'::text,
    coalesce((select name from pn where id=a.project_id),'?')||' · '||a.skill,
    'liefert seit '||a.n_unter||' der letzten Wochen unter Forecast (Ø '||round(abs(a.avg_unter))||'% Lücke) — '
      ||'kein Ausreißer, sondern anhaltende Unterdeckung: strukturell zu wenig Kapazität eingeplant, '
      ||'das kostet dauerhaft Servicelevel. Konfidenz: hoch, mehrere Wochen in Folge.'
    from agg a where a.n_unter >= 3
  union all
  -- 2) Trend Überdeckung
  select 'fc_ueberdeckung_trend'::text,
    coalesce((select name from pn where id=a.project_id),'?')||' · '||a.skill,
    'liegt seit '||a.n_ueber||' der letzten Wochen über Forecast (Ø '||round(a.avg_ueber)||'% Überhang) — '
      ||(case when a.avg_ueber>=80 then 'die Abweichung ist so groß und so beständig, dass eher Verschiedenes gemessen wird als echte Überdeckung (Skill-Zuordnung, Pausen, Stunden-Definition prüfen). Konfidenz: niedrig.'
              else 'anhaltend mehr Kapazität als geplant, die Kosten laufen über Plan. Konfidenz: hoch, mehrere Wochen in Folge.' end)
    from agg a where a.n_ueber >= 3
  union all
  -- 3) Einmalig (jüngste Woche, |dev|>=15%), sofern kein Trend gleicher Richtung läuft
  select
    (case when l.dev<0 then 'fc_unterdeckung' else 'fc_ueberdeckung' end)::text,
    coalesce((select name from pn where id=l.project_id),'?')||' · '||l.skill,
    'Ist '||round(l.ist)||' h gegen Forecast '||round(l.fc)||' h in KW '||l.kw||', '
      ||round(abs(l.dev))||'% '||(case when l.dev<0 then 'unter' else 'über' end)||' Plan'
      ||(case when l.dev>=100 then ', mehr als das Doppelte' else '' end)||' — '
      ||(case
          when l.dev<0 and abs(l.dev)>=80 then 'so wenig, dass eher eine Messlücke als echte Unterdeckung vorliegt (fehlt ein Stunden-Import? falscher Skill?). Konfidenz: niedrig.'
          when l.dev<0 then 'wir liefern die zugesagte Kapazität nicht, das gefährdet Servicelevel und Umsatz. '||(case when a.n_data<=2 then 'Nur '||a.n_data||' Wochen mit Zahlen, entsprechend vorsichtig. Konfidenz: mittel.' else 'Datenbasis solide, die Lücke ist real. Konfidenz: hoch.' end)
          when l.dev>=80 then 'das ist entweder echte Überdeckung oder wir messen Verschiedenes — bei dieser Größe eher Letzteres (Skill-Zuordnung, Pausen, Stunden-Art abgleichen). Konfidenz: niedrig.'
          else 'wir setzen mehr Kapazität ein als geplant, die Kosten liegen über Plan. '||(case when a.n_data<=2 then 'Nur '||a.n_data||' Wochen mit Zahlen, entsprechend vorsichtig. Konfidenz: mittel.' else 'Datenbasis solide, die Abweichung ist real. Konfidenz: hoch.' end)
         end)
    from latest l join agg a on a.project_id=l.project_id and a.skill=l.skill
    where abs(l.dev) >= 15
      and not (l.dev<0 and a.n_unter>=3) and not (l.dev>=0 and a.n_ueber>=3);
end $$;
grant execute on function public.paul_forecast_scan(date) to service_role;
