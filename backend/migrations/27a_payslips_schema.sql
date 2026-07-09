-- =============================================================================
-- Feature 27a — Payslips Schema + RLS + Realtime
-- =============================================================================
-- Legt die payslips-Tabelle an: 1 Row pro (employee_id, month), Status-Flow
-- draft → confirmed → paid (LOCKED). Ersetzt jsr_payslips_v1 in localStorage
-- (Frontend-Migration in 27b-e).
--
-- RLS-Design:
--   - HR/Management/Finance: Full CRUD
--   - Mitarbeiter: SELECT own via app_users.employee_id
--   - Teamlead/Projektleiter: KEIN Access (Privacy — Payroll ist HR-internal)
--   - Kunde: KEIN Access
--
-- Feature-26-Encryption-Kandidaten (Klartext im Schema, transparent-encrypt
-- via Storage-Layer-Hook in Feature 26 nachruesten):
--   - net              (Auszahlungsbetrag — kritisch)
--   - gross            (indirekt Rueckschluss auf Netto)
--   - hourly_rate      (Vertrags-Snapshot, sensitiv)
--   - total_bonuses    (Bonus-Info, HR-vertraulich)
--   - base             (Basis-Bruttolohn)
--   - total_deductions (Abzuege — kombiniert mit gross = net)
--
-- Historie-Snapshot: Employee-Felder (first_name, position, hourly_rate, etc.)
-- werden bewusst redundant im Payslip gespeichert. Wenn ein MA spaeter
-- umbenannt/versetzt wird, bleiben alte Slips historisch korrekt.
--
-- Country-Split (AL/XK Payroll-Config): bleibt in localStorage (Admin-only,
-- selten geaendert) — nicht Teil von 27a.
--
-- Applied via Supabase SQL Editor by the project owner.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1 CREATE TABLE payslips
-- -----------------------------------------------------------------------------
CREATE TABLE payslips (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id         uuid NOT NULL REFERENCES employees(id) ON DELETE RESTRICT,
  month               text NOT NULL,                    -- 'YYYY-MM' Format
  status              text NOT NULL DEFAULT 'draft',    -- draft | confirmed | paid

  -- ─── Employee-Snapshot (Historie: Umbenennung/Wechsel duerfen alte Slips nicht aendern) ───
  first_name          text,
  last_name           text,
  staff_number        text,
  position            text,
  location            text,
  project_id          text,                             -- 25d: text nicht uuid
  email               text,

  -- ─── Vertrags-Snapshot ─────────────────────────────────────────────────
  hourly_rate         numeric,                          -- 26-Encryption-Kandidat
  work_hours          numeric,
  work_model          text,
  contract_start      date,

  -- ─── Zeit-Berechnung ───────────────────────────────────────────────────
  work_days           integer,
  hours_per_day       numeric,
  gross_hours         numeric,

  -- ─── Gehalt ────────────────────────────────────────────────────────────
  base                numeric,                          -- 26-Encryption-Kandidat
  referral_bonus      numeric,
  target_bonus        numeric,
  special_bonus       numeric,
  total_bonuses       numeric,                          -- 26-Encryption-Kandidat
  gross               numeric,                          -- 26-Encryption-Kandidat

  -- ─── Abzuege ───────────────────────────────────────────────────────────
  deduction_tax       numeric,
  deduction_social    numeric,
  deduction_other     numeric,
  total_deductions    numeric,                          -- 26-Encryption-Kandidat
  net                 numeric,                          -- 26-Encryption-Kandidat (kritisch)

  -- ─── Notizen ───────────────────────────────────────────────────────────
  bonus_notes         text,
  deduction_notes     text,

  -- ─── Payment ───────────────────────────────────────────────────────────
  confirmed_at        timestamptz,
  paid_at             timestamptz,
  payment_date        date,
  payment_method      text,

  -- ─── Detail-Berechnung (calcFullPayslip Output, 30+ Felder) ────────────
  calc_detail         jsonb DEFAULT '{}'::jsonb,

  -- ─── Timestamps ────────────────────────────────────────────────────────
  created_at          timestamptz DEFAULT now(),
  updated_at          timestamptz DEFAULT now(),

  -- ─── Uniqueness: 1 Payslip pro (Employee, Monat) ───────────────────────
  UNIQUE(employee_id, month)
);


-- -----------------------------------------------------------------------------
-- §2 Indexes fuer haeufige Queries
-- -----------------------------------------------------------------------------
CREATE INDEX idx_payslips_employee_id ON payslips(employee_id);
CREATE INDEX idx_payslips_month       ON payslips(month);
CREATE INDEX idx_payslips_status      ON payslips(status);


-- -----------------------------------------------------------------------------
-- §3 RLS + Policies
-- -----------------------------------------------------------------------------
ALTER TABLE payslips ENABLE ROW LEVEL SECURITY;

-- HR/Management/Finance: Full CRUD
CREATE POLICY "HR full access payslips" ON payslips
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

-- Mitarbeiter: SELECT own via app_users.employee_id (analog 25a "Employee sees own profile")
CREATE POLICY "Employee sees own payslips" ON payslips
  FOR SELECT TO authenticated
  USING (
    employee_id = (SELECT employee_id FROM app_users WHERE user_id = auth.uid())
  );


-- -----------------------------------------------------------------------------
-- §4 updated_at Trigger (Funktion aus 25a wiederverwendet)
-- -----------------------------------------------------------------------------
CREATE TRIGGER update_payslips_updated_at
  BEFORE UPDATE ON payslips
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


-- -----------------------------------------------------------------------------
-- §5 Realtime Publication
-- -----------------------------------------------------------------------------
ALTER PUBLICATION supabase_realtime ADD TABLE payslips;


-- =============================================================================
-- Verifikation (auskommentiert)
-- =============================================================================
-- (a) Table existiert mit erwarteten Spalten:
--     SELECT column_name, data_type
--     FROM information_schema.columns
--     WHERE table_name='payslips'
--     ORDER BY ordinal_position;
--       → ~32 Spalten (id + employee_id + month + status + 8 snapshot +
--         4 vertrag + 3 zeit + 6 gehalt + 5 abzug + 2 notiz + 4 payment +
--         1 jsonb + 2 timestamps)
--
-- (b) UNIQUE-Constraint (employee_id, month):
--     SELECT conname, contype
--     FROM pg_constraint
--     WHERE conrelid = 'payslips'::regclass AND contype = 'u';
--       → 1 Row: payslips_employee_id_month_key | u
--
-- (c) RLS aktiv + 2 Policies:
--     SELECT polname, polcmd
--     FROM pg_policy p
--     JOIN pg_class c ON c.oid = p.polrelid
--     WHERE c.relname='payslips';
--       → 2 Rows: "HR full access payslips" (*), "Employee sees own payslips" (r)
--
-- (d) Indexes:
--     SELECT indexname FROM pg_indexes
--     WHERE tablename='payslips' ORDER BY indexname;
--       → 4 (payslips_pkey + 3 idx_*)
--
-- (e) updated_at Trigger:
--     SELECT trigger_name FROM information_schema.triggers
--     WHERE event_object_table='payslips';
--       → 1 Row: update_payslips_updated_at
--
-- (f) Realtime Publication:
--     SELECT schemaname, tablename
--     FROM pg_publication_tables
--     WHERE pubname='supabase_realtime' AND tablename='payslips';
--       → 1 Row
--
-- (g) Sanity: Als Mitarbeiter-User (angemeldet) darf man KEINE Fremd-Payslips
--     sehen. Als HR-User sieht man alle:
--     SELECT count(*) FROM payslips;   -- MA: 0 (bis erste eigene existiert), HR: alle
