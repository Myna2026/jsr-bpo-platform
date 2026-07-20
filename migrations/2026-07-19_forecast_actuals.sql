-- =============================================================================
-- Wirtschaftlichkeit: Ist-Zahlen (forecast.monthly_actuals) -> Supabase  2026-07-19
-- =============================================================================
-- Etappe FA1: NUR SCHEMA + RLS. Noch NICHT im Frontend verdrahtet (eigene Etappe FA2).
--   forecast_actuals = monatliche Ist-Zahlen je (Projekt, Monat): Umsatz, Personal-
--   und Sonstige-Kosten, Rechnungsnummer, Notiz. Bisher im localStorage-Blob
--   jsr_forecast_v1 unter monthly_actuals[YYYY-MM][project_id].
--
-- Reale Struktur verifiziert gegen hr.html ProjectProfitability (saveActual 17398 +
-- openEdit 17381): je Zelle { revenue, cost_personnel, cost_other, invoice_nr, notes }.
-- Der aktiv genutzte + beschriebene Teil des forecast-Stores (Wirtschaftlichkeits-View);
-- fixed_costs/location_capacity/future_batches sind eigene Themen (nicht hier).
--
-- RLS (Geschaeftszahlen -> eng wie payroll_inputs, KEIN teamlead/projektleiter/
--   mitarbeiter, kein self-read):
--   "read internal" = management/hr/finance
--   "HR write"      = management/hr/finance
--
-- Idempotent (create table / index / policy IF (NOT) EXISTS + drop policy if exists).
-- Anzuwenden im Supabase SQL Editor (hier NICHT ausgefuehrt).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1 Tabelle
-- -----------------------------------------------------------------------------
create table if not exists public.forecast_actuals (
  id             uuid primary key default gen_random_uuid(),
  project_id     text references public.projects(id) on delete cascade,
  month          text,                             -- 'YYYY-MM'
  revenue        numeric,
  cost_personnel numeric,
  cost_other     numeric,
  invoice_nr     text,
  notes          text,
  updated_at     timestamptz default now(),
  unique(project_id, month)
);
create index if not exists idx_forecast_actuals_project on public.forecast_actuals(project_id);
create index if not exists idx_forecast_actuals_month   on public.forecast_actuals(month);


-- -----------------------------------------------------------------------------
-- §2 RLS — read internal (NUR management/hr/finance) + HR write
-- -----------------------------------------------------------------------------
alter table public.forecast_actuals enable row level security;
drop policy if exists "forecast_actuals read internal" on public.forecast_actuals;
drop policy if exists "forecast_actuals HR write" on public.forecast_actuals;

create policy "forecast_actuals read internal" on public.forecast_actuals
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));

create policy "forecast_actuals HR write" on public.forecast_actuals
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));


-- =============================================================================
-- Verifikation (auskommentiert)
-- =============================================================================
-- (a) Tabelle + Spalten (erwartet 9):
--     select count(*) from information_schema.columns
--      where table_schema='public' and table_name='forecast_actuals';       -- 9
-- (b) RLS + 2 Policies:
--     select c.relname, count(p.polname) from pg_class c
--      left join pg_policy p on p.polrelid=c.oid
--      where c.relname='forecast_actuals' group by c.relname;                -- 2
-- (c) FK project_id -> projects(id) cascade + unique(project_id,month):
--     select conname, contype, confdeltype from pg_constraint
--      where conrelid='public.forecast_actuals'::regclass;
-- =============================================================================
