-- ============================================================================
-- Offboarding / Schnitt 2b Weg A — 7 Payroll-Felder als echte Spalten.
-- Bisher landeten sie in extra jsonb und wurden nie zurückgelesen → der
-- Fixgehalt-Zweig in PayrollView feuerte nie. Diese Spalten machen sie
-- direkt schreib-/lesbar.
--
-- REIHENFOLGE: ZUERST dieses ALTER ausführen + verifizieren, DANN die
-- Migration (employees_payroll_migrate.sql), DANN das Frontend (EMP_COLS).
-- Idempotent (add column if not exists).
-- ============================================================================

alter table public.employees
  add column if not exists fixed_salary     numeric,
  add column if not exists guaranteed_pct   numeric,
  add column if not exists deduct_missing   boolean,
  add column if not exists free_days_month  integer,
  add column if not exists monthly_bonus    numeric,
  add column if not exists overtime_allowed boolean,
  add column if not exists productive_pct   numeric;


-- ---- Verifikation (a): die 7 Spalten existieren ----------------------------
-- Erwartet: 7 Zeilen mit passenden data_types
--   fixed_salary numeric | guaranteed_pct numeric | deduct_missing boolean
--   free_days_month integer | monthly_bonus numeric | overtime_allowed boolean
--   productive_pct numeric
select column_name, data_type
  from information_schema.columns
 where table_schema = 'public'
   and table_name   = 'employees'
   and column_name in ('fixed_salary','guaranteed_pct','deduct_missing',
                       'free_days_month','monthly_bonus','overtime_allowed','productive_pct')
 order by column_name;
