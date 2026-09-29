-- KW 36-40/2026: die Forecast-Werte stammen nachweislich nicht aus der gueltigen Quelle.
-- Der Auftraggeber hat am 2026-09-29 bestaetigt: KW 37-39 wurden von Hand hinterlegt,
-- KW 36 stammt aus dem falschen Blatt ("Planung + Rueckmeldung KW"), das kuenftig ignoriert wird.
-- Ein falsches Ziel im Kundenbericht ist schlechter als gar keines: der Wert wird geleert,
-- die Zeile bleibt als Spur stehen. Zurueckholen = September-/Oktober-Datei neu einlesen.
update public.report_forecast
   set fc_hours = null, planned_hours = null,
       file_name = coalesce(file_name,'') || ' — Wert am 29.09. entfernt (falsche Quelle)'
 where project_id = 'proj_hc_a1b2c3d4' and year = 2026 and kw between 36 and 40;

select skill, kw, coalesce(fc_hours::text,'—') fc, left(file_name,60) quelle
  from public.report_forecast
 where project_id='proj_hc_a1b2c3d4' and year=2026 and kw between 32 and 40 order by skill, kw;
