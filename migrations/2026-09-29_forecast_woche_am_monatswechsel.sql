-- Wochen am Monatswechsel bekamen nie einen Wochenwert.
-- Der Forecast-Import schrieb report_forecast nur fuer Wochen, die INNERHALB EINER Datei vollstaendig
-- waren. KW 40 laeuft vom 28.09. bis 04.10. und ist damit weder in der September- noch in der
-- Oktober-Datei komplett: drei Tage hier, vier Tage dort. Also blieb sie leer, obwohl beide Dateien
-- da waren. Ab jetzt rechnet der Import die Wochenwerte aus forecast_day (Aenderung in hr.html);
-- diese Migration holt den Rueckstand fuer bereits hochgeladene Tage nach.
--
-- Gefuellt werden nur Wochen mit sieben Tagen in forecast_day, bei denen der Wochenwert fehlt.
-- Vorhandene Werte werden NICHT ueberschrieben: sie koennen im Vorschau-Feld von Hand gesetzt sein.
-- Unvollstaendige Wochen bleiben ebenfalls unberuehrt, ihnen fehlt der Nachbarmonat (KW 31 mit zwei
-- Tagen aus Juli, KW 44 mit fuenf Tagen aus November).
with voll as (
  select skill,
         extract(isoyear from work_date)::int as jahr,
         extract(week    from work_date)::int as kw,
         count(*)                              as tage,
         round(sum(fc_total)::numeric, 2)      as fc,
         round(sum(committed)::numeric, 2)     as pl,
         count(committed)                      as pl_n,
         max(file_name)                        as datei
    from public.forecast_day
   where project_id = 'proj_hc_a1b2c3d4'
   group by 1,2,3
  having count(*) = 7
)
insert into public.report_forecast (project_id, skill, year, kw, fc_hours, planned_hours, file_name)
select 'proj_hc_a1b2c3d4', v.skill, v.jahr, v.kw, v.fc,
       case when v.pl_n > 0 then v.pl else null end, v.datei
  from voll v
  left join public.report_forecast rf
    on rf.project_id = 'proj_hc_a1b2c3d4' and rf.skill = v.skill and rf.year = v.jahr and rf.kw = v.kw
 where rf.kw is null;

-- Zeilen, die es schon gibt, deren fc_hours aber NULL ist, nachziehen (der Insert oben laesst sie aus,
-- sonst kollidiert er mit dem Unique-Index auf project_id+skill+year+kw).
update public.report_forecast rf
   set fc_hours = v.fc,
       planned_hours = coalesce(rf.planned_hours, case when v.pl_n > 0 then v.pl else null end),
       file_name = coalesce(rf.file_name, v.datei)
  from (
    select skill, extract(isoyear from work_date)::int as jahr, extract(week from work_date)::int as kw,
           round(sum(fc_total)::numeric,2) as fc, round(sum(committed)::numeric,2) as pl,
           count(committed) as pl_n, max(file_name) as datei
      from public.forecast_day where project_id = 'proj_hc_a1b2c3d4'
     group by 1,2,3 having count(*) = 7) v
 where rf.project_id = 'proj_hc_a1b2c3d4' and rf.skill = v.skill and rf.year = v.jahr and rf.kw = v.kw
   and rf.fc_hours is null;
