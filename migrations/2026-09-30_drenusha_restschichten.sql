-- Drenusha Lecis geplante Schichten nach ihrem Austritt am 16.09.2026 loeschen, wie zuvor bei
-- Ariona Olluri. Acht Schichten vom 17.09. bis 28.09., 60,0 abrechenbare Stunden oder 1.560,00 Euro.
--
-- Am 2026-09-29 waren sie bewusst stehen geblieben ("ein abgeschlossener Zeitraum wird nicht
-- rueckwirkend geaendert"). Mit dem Austrittsfilter vom 2026-09-30 erzeugen sie ohnehin kein Geld
-- mehr, die Abrechnungszahl aendert sich durch das Loeschen also nicht. Was verschwindet, ist der
-- irrefuehrende Plan: acht Schichten fuer jemanden, der nicht mehr da ist.
delete from public.shift_assignments s
using public.employees e
where s.employee_id = e.id
  and s.project_id = 'proj_hc_a1b2c3d4'
  and e.first_name = 'Drenusha' and e.last_name = 'Leci'
  and e.termination_date is not null
  and s.work_date > e.termination_date;
