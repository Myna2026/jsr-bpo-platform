-- =============================================================================
-- Feature 25l-a — Legacy Field Name: id_card → id_number (typed)
-- =============================================================================
-- Ziel: Der Legacy-Feldname `id_card` (Ausweis-Nummer) wandert aus dem
-- extra jsonb in die typisierte Master-Spalte `id_number` (existiert seit 25b).
-- CLAUDE.md-Master-Feld: `id_number`. Abgeschafft wird: `id_card`.
--
-- Reihenfolge in der Feldnamen-Migration:
--   25c/25g — vacation_days_quota, terminated_at, contract_*, bank_*
--   25k     — project_skill, primary_skill, photo_color (typed columns)
--   25l-a   — id_card → id_number (dieser Commit)
--   25l-b   — portal_password Vollcleanup (folgt separat, Security-Fix)
--
-- Semantik "existing typed wins": COALESCE(id_number, extra->>'id_card').
-- NULLIF(...,'') gegen leere Strings als Cast-Source. WHERE extra ? 'id_card'
-- filtert nur relevante Rows.
--
-- Idempotenz: Re-Run auf bereinigtem Bestand → 0 Rows affected.
--
-- Frontend-Analogon: mapLegacyEmployeeFields() in hr.html Block 5 (25l-a
-- Frontend-Commit) macht dasselbe auf der Save-Seite fuer zukuenftige
-- Neuanlagen und LocalStorage-Legacy-Imports.
--
-- Applied via Supabase SQL Editor by the project owner.
-- =============================================================================


BEGIN;


-- -----------------------------------------------------------------------------
-- Data-Migration: extra.id_card → id_number
-- -----------------------------------------------------------------------------
UPDATE employees
SET
  id_number = COALESCE(id_number, NULLIF(extra->>'id_card', '')),
  extra     = extra - 'id_card'
WHERE extra ? 'id_card';


COMMIT;


-- =============================================================================
-- Verifikation (auskommentiert)
-- =============================================================================
-- (a) Keine Legacy-Keys mehr in extra:
--     SELECT COUNT(*) FROM employees WHERE extra ? 'id_card';
--       → 0
--
-- (b) Migrations-Erfolg (bei Rows die id_card in extra hatten):
--     SELECT id, first_name, id_number FROM employees WHERE id_number IS NOT NULL;
--       → id_number befuellt mit ex-id_card-Werten
--
-- (c) Sanity: Test-MA (Diagnose-Baseline hatte kein id_card in extra):
--     SELECT id, first_name, id_number, extra FROM employees;
--       → id_number weiterhin null oder befuellt, extra unveraendert (kein
--         id_card entfernt bei bereinigtem Bestand — 0 UPDATE-Rows erwartet)
