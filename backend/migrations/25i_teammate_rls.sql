-- =============================================================================
-- Feature 25i — Teammate RLS + View for Mitarbeiter-Portal
-- =============================================================================
-- Ziel: mitarbeiter.html liest Kollegen (Team-View, COLS-Ersatz) direkt aus
-- Supabase statt aus localStorage. Voraussetzung fuer Sub-Commit 25i-Frontend.
--
-- Scope-Semantik (aus canChatWith in mitarbeiter.html L1850-53):
--   Ein MA sieht als "Kollege":
--     (c) Personen im eigenen Projekt (same project_id), ODER
--     (b) Personen mit role_keys management/hr (Universal-Chat-Kontakte,
--         Projekt-uebergreifend).
--   Filter: status IN ('active','training').
--   Guard: nur MA-Rolle-User triggern diese Policy.
--
-- Abhaengigkeiten (muessen bereits existieren):
--   - Tabelle employees (25a) mit project_id text (25d), role_keys text[]
--   - Tabelle app_users mit user_id, role_keys, employee_id
--   - Extra-jsonb-Felder function/project_skill/primary_skill/photo_color
--     (aktuell im extra-Sammelbecken — spaetere Migration typisiert diese).
--
-- Anti-Rekursions-Design (analog 25a get_my_project_id + 25e
-- get_my_client_project_id): Der Helper get_my_employee_project_id() ist
-- SECURITY DEFINER → bypassed RLS auf employees + app_users intern. Die
-- Policy selbst hat keinen Selbst-Referenz-Zweig.
--
-- Bewusst separate Funktion (nicht get_my_project_id() reused): Decoupling
-- gegen zukuenftige Semantik-Aenderungen der teamlead-Variante. Bodies sind
-- aktuell identisch — Konsolidierung ist spaetere Aufraeum-Entscheidung.
--
-- Applied via Supabase SQL Editor by the project owner.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1) SECURITY DEFINER helper: liefert project_id des eingeloggten Mitarbeiters
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_my_employee_project_id()
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

REVOKE ALL   ON FUNCTION get_my_employee_project_id() FROM public;
GRANT EXECUTE ON FUNCTION get_my_employee_project_id() TO authenticated;


-- -----------------------------------------------------------------------------
-- 2) Policy: Mitarbeiter sieht Kollegen (Same-Project OR Universal-HR/Mgmt)
-- -----------------------------------------------------------------------------
-- Re-runnable via DROP POLICY IF EXISTS (CREATE POLICY hat kein IF NOT EXISTS).
-- Additive zu 25h-Policies "Employee sees own profile" + "Employee updates own
-- profile" — beide bleiben unveraendert, decken den Self-Case ab.

DROP POLICY IF EXISTS "Employee sees teammates" ON employees;

CREATE POLICY "Employee sees teammates" ON employees
  FOR SELECT TO authenticated
  USING (
    status IN ('active', 'training')
    AND (
      project_id = get_my_employee_project_id()
      OR role_keys && ARRAY['management','hr']::text[]
    )
    AND EXISTS (
      SELECT 1 FROM app_users
      WHERE user_id = auth.uid()
        AND role_keys && ARRAY['mitarbeiter']::text[]
    )
  );


-- -----------------------------------------------------------------------------
-- 3) Column-Scope View fuer Team-View im MA-Portal
-- -----------------------------------------------------------------------------
-- 12-Spalten-Scope aus Q2:
--   id, first_name, last_name, position, function, role_keys,
--   project_id, project_skill, primary_skill,
--   photo_url, photo_color, status
--
-- Nicht getypte Felder (function, project_skill, primary_skill, photo_color)
-- werden aus `extra` jsonb extrahiert. Der Rest von `extra` bleibt privat —
-- der View exponiert nur die 4 Extract-Keys, nicht die volle jsonb.
--
-- Bewusst NICHT im View: email, phone, staff_number (Datenschutz),
-- audios/videos (Kunde-Coaching-Material, nicht Team-relevant),
-- bank/contract/salary/hourly_rate/absences/warnings/extra (privat).
--
-- security_invoker + security_barrier analog 25f — siehe dort fuer Rationale.

DROP VIEW IF EXISTS employees_team_view;

CREATE VIEW employees_team_view
WITH (security_invoker = true, security_barrier = true)
AS
SELECT
  id,
  first_name,
  last_name,
  position,
  role_keys,
  project_id,
  status,
  photo_url,
  extra->>'function'      AS function,
  extra->>'project_skill' AS project_skill,
  extra->>'primary_skill' AS primary_skill,
  extra->>'photo_color'   AS photo_color
FROM employees
WHERE status IN ('active', 'training');


-- -----------------------------------------------------------------------------
-- 4) Zugriff fuer authenticated freischalten
-- -----------------------------------------------------------------------------
-- Row-Level-Filterung uebernimmt die 25i-Policy auf der Basis-Tabelle
-- employees. authenticated-Rolle darf die View selektieren — Row-Sichtbarkeit
-- wird per RLS auf employees kontrolliert (security_invoker!).

GRANT SELECT ON employees_team_view TO authenticated;


-- -----------------------------------------------------------------------------
-- 5) Doku-Kommentar
-- -----------------------------------------------------------------------------
COMMENT ON VIEW employees_team_view IS
  'Column-Scope View fuer mitarbeiter.html Team-View (Feature 25i). '
  'Row-Access via 25i-Policy auf employees. '
  'Extra-Felder function/project_skill/primary_skill/photo_color aktuell '
  'aus extra->> — spaetere Migration typisiert diese Felder.';


-- -----------------------------------------------------------------------------
-- Verifikation nach Ausfuehrung:
--
--   -- (a) Funktion existiert und ist SECURITY DEFINER:
--   SELECT prosecdef, provolatile FROM pg_proc
--   WHERE proname='get_my_employee_project_id';
--     → prosecdef = t (SECURITY DEFINER), provolatile = s (STABLE)
--
--   -- (b) Policy existiert:
--   SELECT polname, polcmd FROM pg_policy p
--   JOIN pg_class c ON c.oid = p.polrelid
--   WHERE c.relname='employees' AND polname='Employee sees teammates';
--     → 1 Row, polcmd = 'r' (SELECT)
--
--   -- (c) View existiert mit security_invoker + security_barrier:
--   SELECT c.relname, c.reloptions
--   FROM pg_class c WHERE c.relname='employees_team_view';
--     → reloptions enthaelt security_invoker=true UND security_barrier=true
--
--   -- (d) GRANT ist gesetzt:
--   SELECT grantee, privilege_type FROM information_schema.role_table_grants
--   WHERE table_name='employees_team_view';
--     → authenticated | SELECT
--
--   -- (e) Sanity: Als MA-User (angemeldet) muss die View
--   -- die eigenen Kollegen liefern und darf NIEMALS Payroll-Felder zeigen:
--   SELECT count(*) FROM employees_team_view;
--     → > 0 (falls Kollegen auf gleichem Projekt existieren)
--   SELECT column_name FROM information_schema.columns
--   WHERE table_name='employees_team_view' ORDER BY ordinal_position;
--     → nur die 12 View-Spalten, keine email/phone/bank/contract/salary/…
-- -----------------------------------------------------------------------------
