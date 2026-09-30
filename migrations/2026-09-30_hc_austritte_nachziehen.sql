-- Nachtrag zur Bereinigung vom 2026-09-29.
-- Damals blieben Drenusha Lecis September-Schichten nach ihrem Austritt (16.09.) stehen, mit der
-- Begruendung, ein abgeschlossener Zeitraum werde nicht rueckwirkend geaendert. Das galt nur fuer
-- die Vergangenheit: zwei dieser Schichten liegen am 29. und 30.09. und damit in der Gegenwart,
-- zusammen 15 Stunden netto oder 390 Euro, die im laufenden Tageszaehler mitlaufen. Die kommen raus.
-- Die Schichten vom 17. bis 28.09. bleiben wie besprochen stehen, dokumentiert in docs/schichtplanung.md.
delete from public.shift_assignments s
using public.employees e
where s.employee_id = e.id
  and s.project_id = 'proj_hc_a1b2c3d4'
  and e.first_name = 'Drenusha' and e.last_name = 'Leci'
  and s.work_date >= date '2026-09-29';

-- Beide sind ausgetreten, standen aber noch auf "active". Statuswert ist 'terminated', nicht
-- 'inactive': 'inactive' meint eine voruebergehende Pause OHNE Austrittsdatum (Elternzeit,
-- Langzeitkrankheit) und laesst die Person in EMPLOYED und damit im Lohnlauf stehen. Alle zwoelf
-- bisherigen Austritte im System tragen 'terminated', alle mit Austrittsdatum.
update public.employees
   set status = 'terminated'
 where (first_name, last_name) in (('Drenusha','Leci'), ('Ariona','Olluri'))
   and termination_date is not null
   and status <> 'terminated';
