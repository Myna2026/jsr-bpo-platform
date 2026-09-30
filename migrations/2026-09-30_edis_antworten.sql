-- Edis Antworten vom 2026-09-30.
--
-- 1 Ardita Hysenaj: keine Prozentregel, sondern eine Obergrenze in Stunden. Hoechstens 6,5 Stunden
--   operativ je Tag, auch wenn mehr geplant ist; weniger ist moeglich. Der Anteil geht deshalb von
--   75 auf 100 Prozent zurueck, und die Grenze uebernimmt die Begrenzung (Feld max_h, neu).
--   Wirkung: an ihren 7-Stunden-Tagen zaehlen 6,5 statt bisher 5,25 Stunden.
update public.app_config
   set value = jsonb_set(value, '{entries}', (
         select jsonb_agg(case when e->>'emp' = '1c5f549e-4e60-43a7-98b0-fd3041c7f1a2'
                               then e || jsonb_build_object('pct', 100, 'max_h', 6.5,
                                      'note', 'hoechstens 6,5 Stunden operativ je Tag, Vorgabe des Auftraggebers')
                               else e end)
           from jsonb_array_elements(value->'entries') e))
 where key = 'jsr_hc_billing_v1';

-- 2 Fitnete Luma ist seit dem 29.08.2026 raus. Sie war bereits geschlossen, aber mit dem 31.08.
--   als Austrittsdatum. Korrigiert auf den 29.08. Keine Auswirkung auf die Abrechnung: ihre letzte
--   Schicht liegt am 28.08.
update public.employees
   set termination_date = date '2026-08-29'
 where first_name = 'Fitnete' and last_name = 'Luma'
   and termination_date is distinct from date '2026-08-29';

-- 3 Drenusha Leci und Ariona Olluri sind geschlossen: Status 'terminated', Austrittsdaten 16.09.
--   und 30.09. Beides steht bereits so, hier nur zur Sicherheit.
update public.employees
   set status = 'terminated'
 where (first_name, last_name) in (('Drenusha','Leci'), ('Ariona','Olluri'))
   and status <> 'terminated';

-- 4 Arben Kelmendi und Valon Gashi arbeiten auf Support. Bei Agenten sind die flachen Felder die
--   Zuordnung (docs/fachmodell/personen-und-datenmodell.md).
update public.employees
   set project_skill = 'support'
 where (first_name, last_name) in (('Arben','Kelmendi'), ('Valon','Gashi'))
   and project_id = 'proj_hc_a1b2c3d4';
