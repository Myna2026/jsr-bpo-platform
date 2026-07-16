-- ============================================================================
-- Blocker 1 / B1 — Snapshot: Fixgehalt in der Payslip-Zeile.
-- Beim Erstellen wird fixed_salary in die payslips-Zeile geschrieben, damit die
-- Render-/Detail-Bewertung den effektiven Stundensatz (fixed_salary/(work_days
-- × hours_per_day)) reproduzierbar aus der gespeicherten Zeile ableiten kann —
-- unabhaengig davon, ob am Mitarbeiter spaeter hourly_rate/fixed_salary aendert.
-- Idempotent (add column if not exists).
-- ============================================================================

alter table public.payslips add column if not exists fixed_salary numeric;


-- ---- Verifikation: die Spalte existiert -----------------------------------
-- Erwartet: 1 Zeile  ->  fixed_salary | numeric
select column_name, data_type
  from information_schema.columns
 where table_schema = 'public'
   and table_name   = 'payslips'
   and column_name  = 'fixed_salary';
