-- report_forecast: geplante Stunden (unsere Rückmeldung) aus Blatt 5 zusätzlich zum FC.
-- Spalte "geplante Stunden" der Auftraggeber-Datei = unsere Rückmeldung (Plan-Stunden je KW).
-- Import füllt planned_hours; der Bericht nutzt sie für die Rückmeldung, sonst Rückfall auf
-- die Formel FTE × 7,5 × Werktage. Additiv/idempotent.
alter table public.report_forecast
  add column if not exists planned_hours numeric;
