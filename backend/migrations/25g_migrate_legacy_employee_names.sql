-- =============================================================================
-- Feature 25g — Legacy Employee Field Names: Data Migration
-- =============================================================================
-- Bereinigt bestehende employees.extra-Payloads von 8 Legacy-Feldnamen und
-- verschiebt die Werte in die Master-Felder (Sub-Commit 25c-b).
--
-- Regel: "Ziel behalten" — COALESCE(target, legacy). Existing wins.
-- Bei jsonb-Merges: jsonb_strip_nulls(legacy_object) || contract/bank, sodass
-- bestehende Keys erhalten bleiben (Right-Side wins beim ||-Operator).
--
-- Idempotent: WHERE-Guard filtert nur Rows mit Legacy-Keys. Re-Run auf einem
-- bereinigten Bestand ist harmlos (0 Rows affected).
--
-- NULLIF(..., '')-Schutz gegen "" → Cast-Error auf numeric/date. Bei jsonb-null
-- (nicht String) liefert extra->>'key' bereits SQL-NULL — strip_nulls raeumt.
--
-- Frontend-Analogon: mapLegacyEmployeeFields() in hr.html (Commit 0791494)
-- macht dasselbe fuer neue/editierte Rows auf der Save-Seite. Dieses SQL
-- bereinigt Bestandsdaten in einem Rutsch.
--
-- Applied via Supabase SQL Editor by the project owner.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1) vacation_days_quota → vacation_days (numeric)
-- -----------------------------------------------------------------------------
UPDATE employees
SET
  vacation_days = COALESCE(vacation_days, NULLIF(extra->>'vacation_days_quota', '')::numeric),
  extra         = extra - 'vacation_days_quota'
WHERE extra ? 'vacation_days_quota';


-- -----------------------------------------------------------------------------
-- 2) terminated_at → termination_date (date)
-- -----------------------------------------------------------------------------
UPDATE employees
SET
  termination_date = COALESCE(termination_date, NULLIF(extra->>'terminated_at', '')::date),
  extra            = extra - 'terminated_at'
WHERE extra ? 'terminated_at';


-- -----------------------------------------------------------------------------
-- 3) contract_start / contract_end / contract_signed_manual → contract jsonb
--    Merge-Semantik: bestehende contract-Keys gewinnen (Right-Side beim ||).
--    Null-Legacy-Werte werden per strip_nulls verworfen — kein Overschreiben
--    mit null.
-- -----------------------------------------------------------------------------
UPDATE employees
SET
  contract = jsonb_strip_nulls(jsonb_build_object(
    'start',         NULLIF(extra->>'contract_start',         ''),
    'end',           NULLIF(extra->>'contract_end',           ''),
    'signed_manual', NULLIF(extra->>'contract_signed_manual', '')
  )) || COALESCE(contract, '{}'::jsonb),
  extra    = extra - 'contract_start' - 'contract_end' - 'contract_signed_manual'
WHERE extra ?| ARRAY['contract_start','contract_end','contract_signed_manual'];


-- -----------------------------------------------------------------------------
-- 4) bank_name / bank_account / bank_currency → bank jsonb  (Option B: iban)
--    CLAUDE.md-Master-Feldnamen fuer bank: {name, iban, bic}.
--    bank_account (Legacy) mapt auf bank.iban (semantisch = Kontonummer/IBAN).
-- -----------------------------------------------------------------------------
UPDATE employees
SET
  bank  = jsonb_strip_nulls(jsonb_build_object(
    'name',     NULLIF(extra->>'bank_name',     ''),
    'iban',     NULLIF(extra->>'bank_account',  ''),
    'currency', NULLIF(extra->>'bank_currency', '')
  )) || COALESCE(bank, '{}'::jsonb),
  extra = extra - 'bank_name' - 'bank_account' - 'bank_currency'
WHERE extra ?| ARRAY['bank_name','bank_account','bank_currency'];


-- -----------------------------------------------------------------------------
-- Verifikation nach Ausfuehrung:
--
--   SELECT count(*) FROM employees
--   WHERE extra ?| ARRAY[
--     'vacation_days_quota','terminated_at',
--     'contract_start','contract_end','contract_signed_manual',
--     'bank_name','bank_account','bank_currency'
--   ];
--   → soll 0 sein
--
--   Test-MA-Snapshot vor Migration:
--     extra = {"vacation_days_quota": 20, "contract_end": null}
--     vacation_days = null, contract = {}, termination_date = null, bank = {}
--
--   Test-MA-Snapshot nach Migration (erwartet):
--     vacation_days   = 20             (Legacy migriert)
--     contract        = {}             (Legacy war null → strip_nulls verwarf)
--     termination_date = null          (kein terminated_at im Legacy)
--     bank            = {}             (kein bank_* im Legacy)
--     extra           = {}             (beide Legacy-Keys entfernt)
-- -----------------------------------------------------------------------------
