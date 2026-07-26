-- payslips.soll_days — Snapshot der abwesenheits-bereinigten Soll-Werktage. VOR dem Code-Deploy.
-- Der Lohnlauf rechnet Ueberstunden ab (Werktage − genehmigte Abwesenheit) × work_hours, nicht
-- mehr ab reiner Mo-Fr-Zaehlung. Damit finalisierte Payslips = Draft, wird der bereinigte
-- Sollwert pro Slip gesnapshottet (analog work_days/hours_per_day). effRate/Stundenwert bleibt
-- bewusst work_days-basiert (Fixgehalt-Stundenwert steigt nicht durch Urlaub).
--
-- REIHENFOLGE: erst diese Migration (Spalte anlegen), DANN Code deployen (savePayslipToDB
-- schreibt soll_days). Umgekehrt -> 400 (PostgREST-Write auf nicht existente Spalte).
-- Bestehende Slips: soll_days bleibt null -> generatePayslipHTML faellt auf work_days zurueck,
-- also KEINE Aenderung an finalisierten Payslips.

alter table public.payslips add column if not exists soll_days numeric;
