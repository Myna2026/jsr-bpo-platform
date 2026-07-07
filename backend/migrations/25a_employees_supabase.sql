-- =============================================================================
-- Feature 25a — Full Supabase Sync for Employees + Client-Accounts
-- =============================================================================
-- Applied via Supabase SQL Editor by the project owner. Base for follow-up
-- sub-features (25b, 25c, ...).
--
-- Clarifications integrated from planning round:
--   1) Teamlead-RLS via SECURITY DEFINER helper (avoids recursive RLS on
--      employees when resolving current user's project_id).
--   2) Typed columns + jsonb payloads (absences, audios, videos, warnings,
--      project_assignments, allowed_shifts, bank, contract) + `extra` jsonb
--      catch-all for unknown fields from jsr_emp_v3.
--   3) Realtime publications for employees, client_accounts, app_users.
--   4) client_accounts schema is already known — no change here.
--   5) app_users.staff_number added conditionally (only if missing).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1) employees table (typed fields + jsonb structured payloads)
-- -----------------------------------------------------------------------------
CREATE TABLE employees (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Grunddaten
  first_name           text NOT NULL,
  last_name            text NOT NULL,
  email                text UNIQUE,
  phone                text,
  staff_number         text,
  role_keys            text[] DEFAULT ARRAY[]::text[],
  project_id           uuid,
  skill                text,
  target_role          text,
  status               text DEFAULT 'active',
  source               text DEFAULT 'manual',
  cv_skills            text[] DEFAULT ARRAY[]::text[],
  hire_date            date,
  termination_date     date,
  location             text,
  photo_url            text,
  about_text           text,
  interests            text[] DEFAULT ARRAY[]::text[],
  -- Zusaetzliche typisierte Felder (Klaerung 2)
  notes                text,
  salary_type          text,
  hourly_rate          numeric,
  work_model           text,
  work_hours           numeric,
  shift_earliest       text,
  shift_latest         text,
  vacation_days        numeric,
  -- Strukturierte Payloads als jsonb (Klaerung 2)
  absences             jsonb DEFAULT '[]'::jsonb,
  audios               jsonb DEFAULT '[]'::jsonb,
  videos               jsonb DEFAULT '[]'::jsonb,
  warnings             jsonb DEFAULT '[]'::jsonb,
  project_assignments  jsonb DEFAULT '[]'::jsonb,
  allowed_shifts       jsonb DEFAULT '[]'::jsonb,
  bank                 jsonb DEFAULT '{}'::jsonb,
  contract             jsonb DEFAULT '{}'::jsonb,
  -- Sammelbecken fuer bisher unbekannte Felder aus jsr_emp_v3
  extra                jsonb DEFAULT '{}'::jsonb,
  -- Timestamps
  created_at           timestamptz DEFAULT now(),
  updated_at           timestamptz DEFAULT now()
);

CREATE INDEX idx_employees_project_id   ON employees(project_id);
CREATE INDEX idx_employees_email        ON employees(email);
CREATE INDEX idx_employees_status       ON employees(status);
CREATE INDEX idx_employees_staff_number ON employees(staff_number);


-- -----------------------------------------------------------------------------
-- 2) app_users.employee_id (ersetzt jsr_emp_user_links_v1)
-- -----------------------------------------------------------------------------
ALTER TABLE app_users
  ADD COLUMN IF NOT EXISTS employee_id uuid NULL REFERENCES employees(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_app_users_employee_id ON app_users(employee_id);

COMMENT ON COLUMN app_users.employee_id IS
  'Verknuepfung zu employees.id (ersetzt jsr_emp_user_links_v1)';


-- -----------------------------------------------------------------------------
-- 3) app_users.staff_number (conditional add — Klaerung 5)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name  = 'app_users'
      AND column_name = 'staff_number'
  ) THEN
    ALTER TABLE app_users ADD COLUMN staff_number text NULL;
    CREATE INDEX idx_app_users_staff_number ON app_users(staff_number);
  END IF;
END $$;


-- -----------------------------------------------------------------------------
-- 4) SECURITY DEFINER helper: resolves current user's project_id
--     (Klaerung 1 — vermeidet rekursive RLS in employees-Policies)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_my_project_id()
RETURNS uuid
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
-- 5) RLS + Policies on employees
-- -----------------------------------------------------------------------------
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;

-- Management/HR/Finance: full CRUD
CREATE POLICY "HR full access employees" ON employees
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM app_users
      WHERE user_id = auth.uid()
        AND role_keys && ARRAY['management','hr','finance']::text[]
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM app_users
      WHERE user_id = auth.uid()
        AND role_keys && ARRAY['management','hr','finance']::text[]
    )
  );

-- Teamlead/Projektleiter: read employees of own project (via SECURITY DEFINER helper)
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

-- Mitarbeiter: nur eigenes Profil lesen
CREATE POLICY "Employee sees own profile" ON employees
  FOR SELECT TO authenticated
  USING (
    id = (SELECT employee_id FROM app_users WHERE user_id = auth.uid())
  );

-- Mitarbeiter: nur eigenes Profil updaten
CREATE POLICY "Employee updates own profile" ON employees
  FOR UPDATE TO authenticated
  USING (
    id = (SELECT employee_id FROM app_users WHERE user_id = auth.uid())
  )
  WITH CHECK (
    id = (SELECT employee_id FROM app_users WHERE user_id = auth.uid())
  );


-- -----------------------------------------------------------------------------
-- 6) updated_at Trigger
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_employees_updated_at
  BEFORE UPDATE ON employees
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


-- -----------------------------------------------------------------------------
-- 7) Realtime publications (Klaerung 3)
-- -----------------------------------------------------------------------------
ALTER PUBLICATION supabase_realtime ADD TABLE employees;
ALTER PUBLICATION supabase_realtime ADD TABLE client_accounts;
ALTER PUBLICATION supabase_realtime ADD TABLE app_users;


-- -----------------------------------------------------------------------------
-- 8) client_accounts: no schema change (Klaerung 4)
-- -----------------------------------------------------------------------------
-- Bestehendes Schema ist bereits verifiziert. Falls die Policy
-- "Client sees own account" fuer Feature 17 noch fehlen sollte,
-- separat anlegen (nicht Teil von 25a).
