-- Bereinigung des HolidayCheck-Schichtplans, beauftragt am 2026-09-29.
-- Hintergrund: der Schichtplan ist die Abrechnungsgrundlage. Wer darin steht, zaehlt, unabhaengig
-- von Status oder Austrittsdatum. Drei Eintraege gehoerten nicht hinein.
--
-- 1 "Portal Testzugang" (Personalnummer TEST-PORTAL, keine protokollierten Stunden) stand mit
--   10 Sales-Schichten im Plan, 75 h netto, davon 67,5 h im September. Alle Schichten raus.
--   Der Zugang selbst bleibt bestehen, nur der Schichtplan wird bereinigt.
-- 2 Drenusha Leci (Austritt 16.09.) und Ariona Olluri (Austritt 30.09.) waren in den Oktober
--   hinein verplant, je 2 Schichten am 01. und 02.10., zusammen 30 h netto. Raus.
--   BEWUSST NICHT angefasst: Drenushas 10 Schichten zwischen dem 17. und 30.09., 75 h netto,
--   rund 1.950 Euro. Entscheidung der Geschaeftsseite vom 2026-09-29: ein abgeschlossener Zeitraum
--   wird nicht rueckwirkend geaendert. Begruendung ausfuehrlich in docs/schichtplanung.md.
delete from public.shift_assignments s
using public.employees e
where s.employee_id = e.id
  and s.project_id = 'proj_hc_a1b2c3d4'
  and (
        (e.first_name = 'Portal' and e.last_name = 'Testzugang')
     or ((e.first_name, e.last_name) in (('Drenusha','Leci'), ('Ariona','Olluri')) and s.work_date >= date '2026-10-01')
      );

-- 3 Arbenit Gashi: freigestellt bezahlt seit 16.09., Austritt 16.09., keine Schicht mehr. Er lief
--   trotzdem auf dem Standardanteil von 100 Prozent. Auf 0, damit nichts nachrutscht.
update public.app_config
   set value = jsonb_set(value, '{entries}',
         coalesce(value->'entries','[]'::jsonb) || jsonb_build_object(
           'id','hcb_arbenit',
           'emp','fd3bb9c7-f5ab-4769-9b46-25beb30353bb',
           'pct', 0,
           'from', null,
           'to', null,
           'note','freigestellt bezahlt seit 16.09.2026, nicht in der Abrechnung'))
 where key = 'jsr_hc_billing_v1'
   and not (value->'entries' @> '[{"emp":"fd3bb9c7-f5ab-4769-9b46-25beb30353bb"}]'::jsonb);
