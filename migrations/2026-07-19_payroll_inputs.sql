-- =============================================================================
-- Lohn-Inputs: localStorage (jsr_payroll_v1 / salaryData) -> Supabase   2026-07-19
-- =============================================================================
-- Etappe PI1: NUR SCHEMA + RLS. Noch NICHT im Frontend verdrahtet (eigene Etappe PI2).
--   payroll_inputs = manuelle Monats-Inputs je (Mitarbeiter, Monat): Boni, Abzuege,
--   Zuschlags-Stunden. KEIN Grundgehalt (das kommt aus employees.hourly_rate/
--   fixed_salary/work_hours). Beim Slip-Erzeugen werden diese Werte in payslips
--   gesnapshottet; payroll_inputs bleibt der editierbare Arbeitsstand davor.
--
-- localStorage-Form: salaryData = { "YYYY-MM": [ {emp_id, month, ...Felder} ] }.
-- Hier flach: 1 Row je (emp_id, month).
--
-- RLS (sensible Lohndaten -> enger als payslips, KEIN Employee-self-read):
--   "read internal"  = NUR management/hr/finance (NICHT teamlead/projektleiter/mitarbeiter)
--   "HR write"       = management/hr/finance
--   Folgt dem payslips-Muster (role_keys && array['management','hr','finance']).
--
-- Idempotent (create table / index / policy IF (NOT) EXISTS + drop policy if exists).
-- Anzuwenden im Supabase SQL Editor (hier NICHT ausgefuehrt).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1 Tabelle
-- -----------------------------------------------------------------------------
create table if not exists public.payroll_inputs (
  id              uuid primary key default gen_random_uuid(),
  emp_id          uuid references public.employees(id) on delete cascade,
  month           text,                            -- 'YYYY-MM'
  referral_bonus  numeric,
  target_bonus    numeric,
  special_bonus   numeric,
  deduction_tax   numeric,
  deduction_social numeric,
  deduction_other numeric,
  overtime_hours  numeric,
  saturday_hours  numeric,
  sunday_hours    numeric,
  holiday_hours   numeric,
  night_hours     numeric,
  notes           text,
  deduction_notes text,
  updated_at      timestamptz default now(),
  unique(emp_id, month)
);
create index if not exists idx_payroll_inputs_emp   on public.payroll_inputs(emp_id);
create index if not exists idx_payroll_inputs_month on public.payroll_inputs(month);


-- -----------------------------------------------------------------------------
-- §2 RLS — read internal (NUR management/hr/finance) + HR write
-- -----------------------------------------------------------------------------
alter table public.payroll_inputs enable row level security;
drop policy if exists "payroll_inputs read internal" on public.payroll_inputs;
drop policy if exists "payroll_inputs HR write" on public.payroll_inputs;

create policy "payroll_inputs read internal" on public.payroll_inputs
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));

create policy "payroll_inputs HR write" on public.payroll_inputs
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));


-- =============================================================================
-- Verifikation (auskommentiert)
-- =============================================================================
-- (a) Tabelle + Spalten (erwartet 17):
--     select count(*) from information_schema.columns
--      where table_schema='public' and table_name='payroll_inputs';         -- 17
-- (b) RLS + 2 Policies:
--     select c.relname, count(p.polname) from pg_class c
--      left join pg_policy p on p.polrelid=c.oid
--      where c.relname='payroll_inputs' group by c.relname;                  -- 2
-- (c) FK emp_id -> employees(id) on delete cascade + unique(emp_id,month):
--     select conname, contype, confdeltype from pg_constraint
--      where conrelid='public.payroll_inputs'::regclass;
-- =============================================================================
