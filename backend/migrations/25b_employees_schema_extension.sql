-- =============================================================================
-- Feature 25b — Employees Schema Extension
-- =============================================================================
-- Extends the 25a employees table with fields identified by the coverage
-- analysis (grep of emp.*, employee.*, newEmp.* / setF() / DUMMY seed).
--
-- Strategy: minimal pragmatic addition — only the fields that appear frequently
-- or are structurally important. Rest is captured by the `extra jsonb`
-- catch-all (see 25a schema) with client-side console.warn for observability.
--
-- Applied via Supabase SQL Editor by the project owner.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1) jsonb payloads (structured arrays/objects)
-- -----------------------------------------------------------------------------
-- abilities:       Skills/Faehigkeiten-Liste am Mitarbeiter (Ursprung des 400-Fehlers)
-- bonuses:         Bonus-Historie (Pauschal-/KPI-/Referral-/Drehrad, siehe CLAUDE.md Gehaltsmodell)
-- referrals:       Referral-Tranchen des Werbenden
-- quality_ratings: QM-Bewertungen
-- hardware:        Zugewiesene Hardware/Devices

ALTER TABLE employees ADD COLUMN IF NOT EXISTS abilities        jsonb DEFAULT '[]'::jsonb;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS bonuses          jsonb DEFAULT '[]'::jsonb;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS referrals        jsonb DEFAULT '[]'::jsonb;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS quality_ratings  jsonb DEFAULT '[]'::jsonb;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS hardware         jsonb DEFAULT '[]'::jsonb;


-- -----------------------------------------------------------------------------
-- 2) typed text columns
-- -----------------------------------------------------------------------------
-- position:  CLAUDE.md-Master-Feld (Agent/Senior Agent/Teamleiter/...),
--            NICHT identisch mit target_role (das ist die CV-Wunsch-Rolle).
-- city:      Wohnort (Adress-Feld)
-- id_number: CLAUDE.md-Master-Name fuer die Ausweis-Nummer (ersetzt id_card)

ALTER TABLE employees ADD COLUMN IF NOT EXISTS position   text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS city       text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS id_number  text;


-- -----------------------------------------------------------------------------
-- 3) Index on position (haeufiger Filter in KPI-/Cockpit-Views)
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_employees_position ON employees(position);


-- -----------------------------------------------------------------------------
-- Anmerkung: alle uebrigen ~41 in der Coverage-Analyse identifizierten Felder
-- (siehe Chat-Uebersicht 25b, Kategorie C) laufen bewusst NICHT als eigene
-- Spalten, sondern werden client-seitig vom saveEmployeeToDB()-Whitelist-Filter
-- ins `extra jsonb` gepackt und dabei einmalig via console.warn protokolliert.
-- Namens-Migration (vacation_days_quota, terminated_at, flach vs. jsonb bei
-- contract/bank) ist Sub-Commit 25c.
-- -----------------------------------------------------------------------------
