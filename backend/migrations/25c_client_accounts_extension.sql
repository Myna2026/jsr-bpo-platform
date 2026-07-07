-- =============================================================================
-- Feature 25c — Client Accounts Schema Extension
-- =============================================================================
-- Extends the existing client_accounts table with 7 text columns that the
-- frontend currently writes but the schema is missing. Without this migration
-- these fields would be silently dropped by the whitelist filter in
-- saveClientAccountToDB() (Sub-Commit 3).
--
-- Missing fields identified during Sub-Commit 3 diagnosis:
--   - contact2_name, contact2_email, contact2_phone  (secondary contact)
--   - address_street, address_city, address_country  (address block)
--   - notes                                          (free-text notes)
--
-- Applied via Supabase SQL Editor by the project owner.
-- =============================================================================


-- Sekundaerer Ansprechpartner (contact person 2)
ALTER TABLE client_accounts ADD COLUMN IF NOT EXISTS contact2_name    text;
ALTER TABLE client_accounts ADD COLUMN IF NOT EXISTS contact2_email   text;
ALTER TABLE client_accounts ADD COLUMN IF NOT EXISTS contact2_phone   text;

-- Adress-Block
ALTER TABLE client_accounts ADD COLUMN IF NOT EXISTS address_street   text;
ALTER TABLE client_accounts ADD COLUMN IF NOT EXISTS address_city     text;
ALTER TABLE client_accounts ADD COLUMN IF NOT EXISTS address_country  text;

-- Freitext-Notizen
ALTER TABLE client_accounts ADD COLUMN IF NOT EXISTS notes            text;


-- -----------------------------------------------------------------------------
-- Anmerkung: keine RLS/Policy-Aenderung noetig — neue Spalten erben die
-- bestehenden Policies der client_accounts-Tabelle. Kein Realtime-Change —
-- neue Spalten sind automatisch Teil der Publication (falls aktiv).
-- Frontend-Feld `created` (text) wird bewusst NICHT als neue Spalte angelegt —
-- die DB-managed `created_at`-Timestamp uebernimmt diese Rolle. Namens-Mapping
-- (created → created_at) faellt in eine spaetere Feldnamen-Migration.
-- -----------------------------------------------------------------------------
