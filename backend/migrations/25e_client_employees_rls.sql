-- =============================================================================
-- Feature 25e — Client-Role RLS Access to Employees
-- =============================================================================
-- Ziel: Kunde-User (role_keys enthaelt 'kunde') sehen die active/training-
-- Mitarbeiter des eigenen Projekts. Voraussetzung fuer Sub-Commit 4c
-- (client.html direct Supabase read fuer employees).
--
-- Abhaengigkeiten (muessen bereits existieren):
--   - Tabelle employees (aus 25a) mit project_id text (aus 25d)
--   - Tabelle client_accounts mit id + project_id text (bereits vorhanden)
--   - Tabelle app_users mit user_id + role_keys + client_id
--     → kurz vor Run pruefen mit:
--       SELECT column_name FROM information_schema.columns
--       WHERE table_name='app_users' AND column_name='client_id';
--
-- Anti-Rekursions-Design:
--   Der Helper get_my_client_project_id() ist SECURITY DEFINER →
--   bypassed RLS auf app_users + client_accounts intern. Die Policy
--   selbst hat keinen Selbst-Referenz-Zweig auf employees.
--
-- Applied via Supabase SQL Editor by the project owner.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1) SECURITY DEFINER helper: liefert project_id des eingeloggten Kunden
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_my_client_project_id()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT ca.project_id
  FROM app_users au
  JOIN client_accounts ca ON ca.id = au.client_id
  WHERE au.user_id = auth.uid()
  LIMIT 1;
$$;

REVOKE ALL   ON FUNCTION get_my_client_project_id() FROM public;
GRANT EXECUTE ON FUNCTION get_my_client_project_id() TO authenticated;


-- -----------------------------------------------------------------------------
-- 2) Policy: kunde sieht active/training-Mitarbeiter des eigenen Projekts
-- -----------------------------------------------------------------------------
-- Re-runnable via DROP POLICY IF EXISTS (CREATE POLICY hat kein IF NOT EXISTS).

DROP POLICY IF EXISTS "Client sees employees on their project" ON employees;

CREATE POLICY "Client sees employees on their project" ON employees
  FOR SELECT TO authenticated
  USING (
    status IN ('active', 'training')
    AND project_id = get_my_client_project_id()
    AND EXISTS (
      SELECT 1 FROM app_users
      WHERE user_id = auth.uid()
        AND role_keys && ARRAY['kunde']::text[]
    )
  );


-- -----------------------------------------------------------------------------
-- Anmerkung: Column-Scope faellt Frontend-seitig. client.html wird in
-- Sub-Commit 4c mit `.select('id, first_name, last_name, position, skill,
-- photo_url, audios, videos, project_id, status')` arbeiten — Row kommt zwar
-- voll aus RLS, aber nur die relevanten Felder wandern uebers Netz.
-- Bei zukuenftig sensiblen Feldern (Gehalt, Bank, contract) waere ein
-- employees_client_view als naechster Haerteschritt sinnvoll (25f/26).
-- -----------------------------------------------------------------------------
