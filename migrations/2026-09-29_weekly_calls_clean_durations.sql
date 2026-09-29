-- Kaputte Call-Werte entfernen: "Outbound" und "Alert - No Answer" sind im Auftraggeber-Export
-- seit KW 36/2026 ZEITDAUERN, keine Stueckzahlen. Der Importer hat sie als Ganzzahl gelesen und
-- dabei die Trennzeichen gestrichen: aus 00:04:39.745 wurde 439745.
--
-- Nachweis: bis KW 35 sind die Werte plausibel (max. 65 Outbound, 3 No Answer), ab KW 36 liegen sie
-- bei bis zu 1.500.000. Jeder Wert laesst sich exakt in eine Uhrzeit zurueckrechnen.
-- answered, held, transferred und die avg_*_sec-Spalten sind NICHT betroffen und bleiben.
--
-- Die ganze Spalte wird geleert, nicht nur die grossen Werte: auch eine 432 waere in diesen Wochen
-- der Rest einer Dauer (00:00:00.432) und keine echte Anzahl. Lieber leer als falsch.
update public.weekly_calls
   set outbound = null, no_answer = null
 where project_id = 'proj_hc_a1b2c3d4'
   and year = 2026 and kw >= 36
   and (outbound is not null or no_answer is not null);

select kw, count(*) zeilen,
       count(outbound) mit_outbound, count(no_answer) mit_no_answer, count(answered) mit_answered
  from public.weekly_calls
 where project_id='proj_hc_a1b2c3d4' and year=2026 and kw between 34 and 40
 group by 1 order by 1;
