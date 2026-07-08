-- =============================================================================
-- Feature 25f — Employees Client-Facing View (Column-Scope Härtung)
-- =============================================================================
-- Ziel: Kunde-Portal liest employees aus einer View mit definiertem
-- Column-Scope, statt aus der Raw-Tabelle mit clientseitigem .select().
-- Verhindert Column-Bypass durch manipulierten Client-Code.
--
-- Design:
--   - View filtert Column-Scope (10 Spalten) + status IN ('active','training')
--     serverseitig.
--   - security_invoker = true: Row-Level-RLS (25e Policy) der employees-Tabelle
--     gilt fuer den anfragenden User, nicht fuer den View-Owner. Ohne diese
--     Option wuerde die View als supabase_admin/postgres laufen und RLS
--     bypassen — genau das Gegenteil unseres Ziels.
--   - security_barrier = true: PG-Planner darf User-WHERE-Predikate nicht
--     VOR den View-Filtern ausfuehren (verhindert potenzielle Info-Leaks
--     ueber leaky functions in User-Predikaten).
--
-- Bekannte Einschraenkung: Realtime funktioniert nur auf Tabellen, nicht Views.
-- client.html subscribed weiterhin employees-Table-Events, filtert die
-- Payload clientseitig auf die 10 View-Columns. Das ist "clean state", keine
-- Security-Barriere — die Full-Row liegt beim WebSocket-Empfang bereits vor.
-- Wer harten Realtime-Column-Scope will, muesste per row-payload-Filter auf
-- Publication-Level ansetzen (separates spaeteres Vorhaben).
--
-- Applied via Supabase SQL Editor by the project owner.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1) View idempotent neu anlegen
-- -----------------------------------------------------------------------------
DROP VIEW IF EXISTS employees_client_view;

CREATE VIEW employees_client_view
WITH (security_invoker = true, security_barrier = true)
AS
SELECT
  id,
  first_name,
  last_name,
  position,
  skill,
  photo_url,
  audios,
  videos,
  project_id,
  status
FROM employees
WHERE status IN ('active', 'training');


-- -----------------------------------------------------------------------------
-- 2) Zugriff fuer authenticated freischalten
-- -----------------------------------------------------------------------------
-- Die Row-Level-Filterung uebernimmt die 25e-Policy auf der Basis-Tabelle
-- employees. authenticated-Rolle darf die View selektieren — Row-Sichtbarkeit
-- wird per RLS auf employees kontrolliert (security_invoker!).

GRANT SELECT ON employees_client_view TO authenticated;


-- -----------------------------------------------------------------------------
-- 3) Doku-Kommentar
-- -----------------------------------------------------------------------------
COMMENT ON VIEW employees_client_view IS
  'Column-Scope View fuer client.html (Feature 25f). '
  'Row-Access via 25e-Policy auf employees. '
  'Realtime bleibt auf employees-Tabelle — clientseitig Column-gefiltert.';
