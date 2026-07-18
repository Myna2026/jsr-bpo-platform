-- =============================================================================
-- Performance RLS-Nachschaerfung: MA lesen nur eigene kpi_entries   2026-07-18
-- =============================================================================
-- Folge-Migration zu migrations/2026-07-18_performance.sql (P1).
--
-- Problem: Die P1-Policy "kpi_entries read internal" listet die Rolle
-- 'mitarbeiter' mit auf -> ein MA koennte die KPI-Werte ALLER Kollegen lesen.
--
-- Ziel:
--   - Rolle 'mitarbeiter': SELECT NUR auf eigene Zeilen (emp_id = eigene
--     employee_id) — Muster exakt von payslips gespiegelt
--     (backend/migrations/27a_payslips_schema.sql:131-136,
--      "Employee sees own payslips": ungated Self-SELECT ueber app_users).
--   - Rollen management/hr/finance/teamlead/projektleiter: voller Lesezugriff
--     (read internal OHNE 'mitarbeiter').
--   - Write (management/hr/finance) aus P1 bleibt unveraendert.
--   - kpi_config bleibt fuer ALLE internen Rollen lesbar (KPI-Definitionen
--     sind keine personenbezogenen Daten) -> hier NICHT angefasst.
--
-- Idempotent (drop policy if exists vor create; enable rls ist no-op).
-- Anzuwenden im Supabase SQL Editor (hier NICHT ausgefuehrt).
-- =============================================================================


alter table public.kpi_entries enable row level security;

-- Alte, zu weit gefasste Read-Policy entfernen (listete 'mitarbeiter' mit).
drop policy if exists "kpi_entries read all authenticated" on public.kpi_entries;
drop policy if exists "kpi_entries read internal" on public.kpi_entries;
drop policy if exists "kpi_entries self read" on public.kpi_entries;

-- (1) Interne Rollen OHNE 'mitarbeiter' -> voller Lesezugriff auf alle Zeilen.
create policy "kpi_entries read internal" on public.kpi_entries
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance','teamlead','projektleiter']));

-- (2) Self-SELECT: jede/r sieht NUR eigene Zeilen (emp_id = eigene
--     employee_id). Fuer 'mitarbeiter' ist dies der einzige Lesezugriff;
--     fuer die internen Rollen aus (1) redundant (deren Policy ist Obermenge).
--     Ungated wie das payslips-Muster (RLS-Policies sind ODER-verknuepft).
create policy "kpi_entries self read" on public.kpi_entries
  for select to authenticated
  using (emp_id = (select employee_id from app_users where user_id = auth.uid()));


-- =============================================================================
-- Verifikation (auskommentiert)
-- =============================================================================
-- (a) Policies auf kpi_entries (erwartet: read internal, self read, HR write):
--     select polname, polcmd from pg_policy
--      where polrelid='public.kpi_entries'::regclass order by polname;
--       -> "kpi_entries HR write" (a/all), "kpi_entries read internal" (r),
--          "kpi_entries self read" (r)
-- (b) 'mitarbeiter' NICHT mehr in der read-internal-Rollenliste:
--     select pg_get_expr(polqual, polrelid) from pg_policy
--      where polrelid='public.kpi_entries'::regclass
--        and polname='kpi_entries read internal';
--       -> enthaelt management/hr/finance/teamlead/projektleiter, KEIN 'mitarbeiter'
-- (c) kpi_config unveraendert (mitarbeiter darf weiter lesen):
--     select polname from pg_policy where polrelid='public.kpi_config'::regclass;
--       -> "kpi_config read internal", "kpi_config HR write"
-- =============================================================================
