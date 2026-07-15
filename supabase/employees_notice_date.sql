-- ============================================================================
-- Offboarding / Schnitt 2, Teil A — Kündigungsdatum an employees
-- notice_date = Kündigungsdatum (die Kündigungsfrist rechnet ab hier).
-- STRIKT getrennt von termination_date = Austrittsdatum (= letzter Tag).
-- Idempotent. Kein Frontend-Bezug — nur die Spalte.
-- ============================================================================

alter table public.employees add column if not exists notice_date date;


-- ---- Verifikation (Ausgabe posten) -----------------------------------------
-- Erwartet: eine Zeile notice_date | date | YES
select column_name, data_type, is_nullable
  from information_schema.columns
 where table_schema = 'public'
   and table_name   = 'employees'
   and column_name  = 'notice_date';
