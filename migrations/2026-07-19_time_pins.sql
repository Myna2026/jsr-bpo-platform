-- =============================================================================
-- Stempeluhr: PINs -> Supabase (Basis fuer server-autoritatives Stempeln)  2026-07-19
-- =============================================================================
-- Etappe ST1: NUR SCHEMA + RLS. Noch NICHT verdrahtet (RPCs = ST2, stempel.html = ST3).
--   time_pins = PIN je Mitarbeiter (aus jsr_pins_v1 { [emp.id]: {code, changed} }),
--   erweitert um Brute-Force-Schutz (failed_attempts + locked_until).
--
-- Zweck: Die Zeiterfassung dient vorerst NUR der internen Uebersicht (Anwesenheit,
-- Pausenverhalten, Puenktlichkeit, Soll-Stunden-Erfuellung) -> KEINE Lohnwirkung.
-- Der PIN ist reine Kiosk-Identifikation am Tablet, kein abrechnungsrelevantes Datum.
--
-- SICHERHEIT — diese Tabelle ist die Auth-Quelle der Stempeluhr:
--   * KEIN anon-Zugriff, KEIN mitarbeiter-Read. Nur management/hr/finance.
--   * Das Tablet (anon, ohne Login) liest sie NIE direkt. Der Abgleich PIN->MA laeuft
--     ausschliesslich ueber SECURITY-DEFINER-RPCs (ST2: lookup_pin / stamp_by_pin),
--     die als Owner laufen und RLS umgehen -> die PIN-Liste wird nie exponiert.
--   * failed_attempts/locked_until werden von den RPCs gepflegt (Lockout nach N Fehlversuchen).
--
-- Idempotent (create table / policy IF (NOT) EXISTS + drop policy if exists).
-- Anzuwenden im Supabase SQL Editor (hier NICHT ausgefuehrt).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1 Tabelle
-- -----------------------------------------------------------------------------
create table if not exists public.time_pins (
  emp_id          uuid primary key references public.employees(id) on delete cascade,
  code            text,                            -- 4-stellig
  changed         date,
  failed_attempts integer default 0,
  locked_until    timestamptz,                     -- null = nicht gesperrt
  updated_at      timestamptz default now(),
  unique(code)                                     -- kein PIN doppelt vergeben
);


-- -----------------------------------------------------------------------------
-- §2 RLS — nur management/hr/finance (read + write), sonst NICHTS
-- -----------------------------------------------------------------------------
alter table public.time_pins enable row level security;
drop policy if exists "time_pins HR access" on public.time_pins;
create policy "time_pins HR access" on public.time_pins
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));


-- =============================================================================
-- Verifikation (auskommentiert)
-- =============================================================================
-- (a) Tabelle + Spalten (erwartet 6):
--     select count(*) from information_schema.columns
--      where table_schema='public' and table_name='time_pins';              -- 6
-- (b) RLS aktiv + genau 1 Policy:
--     select c.relname, c.relrowsecurity, count(p.polname) from pg_class c
--      left join pg_policy p on p.polrelid=c.oid
--      where c.relname='time_pins' group by c.relname, c.relrowsecurity;     -- t | 1
-- (c) PK emp_id -> employees(id) cascade + unique(code):
--     select conname, contype, confdeltype from pg_constraint
--      where conrelid='public.time_pins'::regclass;
-- =============================================================================
