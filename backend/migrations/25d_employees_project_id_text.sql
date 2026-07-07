-- =============================================================================
-- Feature 25d — Employees project_id Type Alignment (uuid → text)
-- =============================================================================
-- Ziel: employees.project_id text-typ, damit es mit client_accounts.project_id
-- (text) verglichen werden kann. Voraussetzung fuer Sub-Commit 4b (Client-RLS
-- Policy) und Sub-Commit 4c (client.html Employees-Filter via project_id).
--
-- Datenmigration: keine — SELECT DISTINCT project_id ... COUNT = 0 (alle NULL).
--
-- Abhaengigkeiten, die die ALTER-Operation blockieren wuerden:
--   1) Policy "Teamlead sees project employees" auf employees referenziert
--      project_id in ihrer USING-Clause → muss vorher gedropt werden.
--   2) Helper-Function get_my_project_id() ist als RETURNS uuid deklariert und
--      selektiert intern employees.project_id → nach ALTER wuerde intern text
--      zurueckkommen, was mit uuid-Signatur mismatched. Signaturaenderung
--      erfordert DROP + CREATE (kein CREATE OR REPLACE bei Return-Typ-Aenderung).
--
-- Reihenfolge unten spiegelt diese Abhaengigkeiten:
--   Policy droppen → Function droppen → ALTER TABLE → Index → Function neu
--   (RETURNS text) → Policy neu (kein Cast noetig, beide Seiten text).
--
-- Applied via Supabase SQL Editor by the project owner.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1) Policy droppen (referenziert project_id im USING-Ausdruck)
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Teamlead sees project employees" ON employees;


-- -----------------------------------------------------------------------------
-- 2) Helper-Function droppen (Return-Typ aendert sich uuid → text)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_my_project_id();


-- -----------------------------------------------------------------------------
-- 3) Column-Typ aendern uuid → text
-- -----------------------------------------------------------------------------
ALTER TABLE employees
  ALTER COLUMN project_id TYPE text
  USING project_id::text;


-- -----------------------------------------------------------------------------
-- 4) Index neu anlegen (der alte war auf uuid-Spalte)
-- -----------------------------------------------------------------------------
DROP INDEX IF EXISTS idx_employees_project_id;
CREATE INDEX idx_employees_project_id ON employees(project_id);


-- -----------------------------------------------------------------------------
-- 5) Helper-Function neu anlegen — Return-Typ text (Rest identisch zu 25a)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_my_project_id()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT e.project_id
  FROM employees e
  JOIN app_users au ON au.employee_id = e.id
  WHERE au.user_id = auth.uid()
  LIMIT 1;
$$;

REVOKE ALL   ON FUNCTION get_my_project_id() FROM public;
GRANT EXECUTE ON FUNCTION get_my_project_id() TO authenticated;


-- -----------------------------------------------------------------------------
-- 6) Policy neu anlegen (beide Seiten text — kein Cast noetig)
-- -----------------------------------------------------------------------------
CREATE POLICY "Teamlead sees project employees" ON employees
  FOR SELECT TO authenticated
  USING (
    project_id = get_my_project_id()
    AND EXISTS (
      SELECT 1 FROM app_users
      WHERE user_id = auth.uid()
        AND role_keys && ARRAY['teamlead','projektleiter']::text[]
    )
  );


-- -----------------------------------------------------------------------------
-- Anmerkung: Client-seitig (Sub-Commit 4a Frontend-Anteil in hr.html):
-- `project_id` ist bereits aus EMP_UUID_COLS entfernt (Commit bec853e).
-- Kein weiterer Frontend-Change durch die SQL-Erweiterung noetig — die
-- zusaetzlichen DROPs/CREATEs sind rein server-side.
-- -----------------------------------------------------------------------------
