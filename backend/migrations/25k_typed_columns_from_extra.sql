-- =============================================================================
-- Feature 25k — Typed Columns from extra: project_skill / primary_skill / photo_color
-- =============================================================================
-- Ziel: 3 haeufig gelesene Felder aus dem `extra jsonb`-Sammelbecken in
-- typisierte text-Spalten heben. Vereinfacht employees_team_view (25i)
-- (kein extra->>-Extract mehr fuer diese 3) und _pickTeamCols in
-- mitarbeiter.html (kein Fallback-Chain mehr).
--
-- Scope (aus 25k-Diagnose Q1):
--   INKLUDIERT: project_skill, primary_skill, photo_color
--   AUSGESCHLOSSEN: function
--     → kein HR-Write-Pfad im Bestand, nur client.html-Dummy-Data setzt es;
--       getEmpRole hat position-basierten Regex-Fallback der dasselbe liefert.
--       function bleibt weiterhin per extra->>'function' AS function im View.
--
-- Reihenfolge (kritisch — Race-Fenster):
--   1. Dieses SQL zuerst manuell in Supabase ausfuehren.
--   2. Dann Frontend-Commit (hr.html EMP_COLS erweitern +
--      mitarbeiter.html _pickTeamCols vereinfachen) pushen.
--   Wenn Frontend zuerst live geht: hr.html schreibt project_skill in eine
--   noch nicht existierende Spalte → 400 Save-Error.
--   Wenn zwischen (1) und (2) neue MA angelegt werden: Werte landen im extra
--   statt in typed. §5 unten enthaelt auskommentiertes Race-Cleanup.
--
-- Idempotenz: ADD COLUMN IF NOT EXISTS, WHERE-Guard auf UPDATEs, DROP+CREATE
-- View. Re-Run auf bereinigtem Bestand → 0 Affected Rows in UPDATEs.
--
-- Applied via Supabase SQL Editor by the project owner.
-- =============================================================================


BEGIN;


-- -----------------------------------------------------------------------------
-- §1 ADD COLUMN IF NOT EXISTS — 3 typisierte text-Spalten
-- -----------------------------------------------------------------------------
ALTER TABLE employees ADD COLUMN IF NOT EXISTS project_skill text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS primary_skill text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS photo_color   text;


-- -----------------------------------------------------------------------------
-- §2 Data-Migration extra → typed columns
-- -----------------------------------------------------------------------------
-- Semantik "existing typed wins": COALESCE(typed, extra) → nur befuellen wenn
-- typed leer. NULLIF(..., '') vermeidet leere Strings als Wert.
-- WHERE extra ? 'key' filtert nur relevante Rows. Bei jsonb-null (nicht String)
-- liefert extra->>'key' bereits SQL-NULL — NULLIF ist zusaetzlicher Schutz.

UPDATE employees SET
  project_skill = COALESCE(project_skill, NULLIF(extra->>'project_skill', '')),
  extra         = extra - 'project_skill'
WHERE extra ? 'project_skill';

UPDATE employees SET
  primary_skill = COALESCE(primary_skill, NULLIF(extra->>'primary_skill', '')),
  extra         = extra - 'primary_skill'
WHERE extra ? 'primary_skill';

UPDATE employees SET
  photo_color = COALESCE(photo_color, NULLIF(extra->>'photo_color', '')),
  extra       = extra - 'photo_color'
WHERE extra ? 'photo_color';


-- -----------------------------------------------------------------------------
-- §3 View-Recreate: direkte typed columns statt extra->>-Extract
-- -----------------------------------------------------------------------------
-- Column-Reihenfolge identisch zu 25i (id, first_name, last_name, position,
-- role_keys, project_id, status, photo_url, function, project_skill,
-- primary_skill, photo_color) — 25k tauscht nur die Datenquellen fuer die
-- letzten 3 Felder aus, kein API-Breaking-Change.
--
-- function bleibt aus extra (Q1a: nicht typisieren).

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
  extra->>'function' AS function,
  project_skill,
  primary_skill,
  photo_color
FROM employees
WHERE status IN ('active', 'training');


-- -----------------------------------------------------------------------------
-- §4 GRANT SELECT auf View
-- -----------------------------------------------------------------------------
-- Row-Level-Filterung uebernimmt weiterhin die 25i-Policy auf employees
-- (security_invoker!) — hier nur Table-Level-Grant fuer authenticated.

GRANT SELECT ON employees_team_view TO authenticated;

COMMENT ON VIEW employees_team_view IS
  'Column-Scope View fuer mitarbeiter.html Team-View (25i + 25k). '
  'project_skill/primary_skill/photo_color seit 25k typisiert; '
  'function weiterhin aus extra (kein HR-Write-Pfad).';


COMMIT;


-- =============================================================================
-- §5 OPTIONAL — Race-Fenster-Cleanup (auskommentiert)
-- =============================================================================
-- NUR ausfuehren falls zwischen §1-§4 Deploy und Frontend-Deploy neue Rows
-- angelegt wurden, die project_skill/primary_skill/photo_color noch ins
-- extra jsonb geschrieben haben. Vorher pruefen:
--
--   SELECT COUNT(*) FROM employees
--   WHERE extra ?| ARRAY['project_skill','primary_skill','photo_color'];
--
-- Wenn Ergebnis > 0 → nachfolgendes Statement-Trio auskommentieren und laufen
-- lassen. Semantik identisch zu §2 (COALESCE + strip).
--
-- UPDATE employees SET
--   project_skill = COALESCE(project_skill, NULLIF(extra->>'project_skill', '')),
--   extra         = extra - 'project_skill'
-- WHERE extra ? 'project_skill';
--
-- UPDATE employees SET
--   primary_skill = COALESCE(primary_skill, NULLIF(extra->>'primary_skill', '')),
--   extra         = extra - 'primary_skill'
-- WHERE extra ? 'primary_skill';
--
-- UPDATE employees SET
--   photo_color = COALESCE(photo_color, NULLIF(extra->>'photo_color', '')),
--   extra       = extra - 'photo_color'
-- WHERE extra ? 'photo_color';


-- =============================================================================
-- §6 Verifikation nach Ausfuehrung (auskommentiert)
-- =============================================================================
-- (a) Spalten existieren und sind text:
--     SELECT column_name, data_type
--     FROM information_schema.columns
--     WHERE table_name='employees'
--       AND column_name IN ('project_skill','primary_skill','photo_color')
--     ORDER BY column_name;
--       → 3 Rows, alle data_type = 'text'
--
-- (b) Keine Legacy-Keys mehr in extra:
--     SELECT COUNT(*) FROM employees
--     WHERE extra ?| ARRAY['project_skill','primary_skill','photo_color'];
--       → 0
--
-- (c) View hat 12 Spalten in erwarteter Reihenfolge:
--     SELECT column_name FROM information_schema.columns
--     WHERE table_name='employees_team_view' ORDER BY ordinal_position;
--       → id, first_name, last_name, position, role_keys, project_id,
--         status, photo_url, function, project_skill, primary_skill, photo_color
--
-- (d) View-Optionen weiterhin gesetzt:
--     SELECT c.relname, c.reloptions FROM pg_class c
--     WHERE c.relname='employees_team_view';
--       → reloptions enthaelt security_invoker=true UND security_barrier=true
--
-- (e) Diagnose-Query "wieviele Rows hatten die Legacy-Keys" (Sanity):
--     Vorher (Diagnose 25k): 1 Row mit project_skill, 1 Row mit photo_color.
--     Erwartung nach §2: beide Rows haben Werte in typed columns statt extra.
--     SELECT id, project_skill, primary_skill, photo_color, extra
--     FROM employees LIMIT 5;
--       → project_skill/photo_color befuellt, extra-Keys weg
