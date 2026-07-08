-- =============================================================================
-- Feature 25l-b — Security-Fix: portal_password komplett aus extra entfernen
-- =============================================================================
-- Security-Rationale:
--   Passwoerter gehoeren ausschliesslich in Supabase Auth (auth.users), niemals
--   als Klartext in einer Business-Tabelle wie employees.extra. Der historisch
--   gewachsene Key portal_password stammt aus einer Pre-Supabase-Auth-Ära und
--   ist toter Code + Sicherheitsrisiko: Klartext-Passwoerter in einer jsonb-
--   Spalte sind ueber jeden SELECT auslesbar und landen potenziell in Logs,
--   Backups, Realtime-Payloads.
--
-- Kein Data-Migration — Passwoerter werden nicht "verschoben". Der Wert wird
-- ersatzlos verworfen. Portal-Auth laeuft komplett ueber sb.auth (verifiziert
-- in hr.html/mitarbeiter.html/client.html seit 25a).
--
-- Reihenfolge in der Feldnamen-Migration:
--   25c/25g — vacation_days_quota, terminated_at, contract_*, bank_*
--   25k     — project_skill, primary_skill, photo_color (typed columns)
--   25l-a   — id_card → id_number
--   25l-b   — portal_password Security-Removal (dieser Commit)
--
-- Idempotenz: WHERE-Guard auf extra ? 'portal_password'. Re-Run auf
-- bereinigtem Bestand → 0 Affected Rows.
--
-- Frontend-Analogon:
--   - hr.html Vollcleanup (Commit 25l-b hr.html): Seeds, Form-Inputs, Init,
--     CV-Promote, CSV-Import, Onboarding-Checklist alle entfernt
--   - mapLegacyEmployeeFields Block 6 (Guard): fangt Legacy-Save-Pfade ab
--   - dummy_loader.html + setup.html (Commit 25l-b nebenmodule)
--
-- Applied via Supabase SQL Editor by the project owner.
-- =============================================================================


BEGIN;


-- -----------------------------------------------------------------------------
-- Security-Fix: portal_password komplett aus extra entfernen
-- -----------------------------------------------------------------------------
UPDATE employees
SET extra = extra - 'portal_password'
WHERE extra ? 'portal_password';


COMMIT;


-- =============================================================================
-- Verifikation (auskommentiert)
-- =============================================================================
-- (a) Keine portal_password-Keys mehr in extra:
--     SELECT COUNT(*) FROM employees WHERE extra ? 'portal_password';
--       → 0
--
-- (b) Test-MA war Baseline mit portal_password=null in extra:
--     SELECT id, first_name, extra FROM employees;
--       → extra enthaelt kein portal_password-Key mehr (auch wenn Wert
--         vorher null war, wird der Key selbst per `extra - 'portal_password'`
--         entfernt)
--
-- (c) Sanity-Cross-Check gegen auth.users:
--     SELECT COUNT(*) FROM auth.users;
--       → Supabase-Auth-Table existiert und ist die einzige Password-Quelle
