-- =============================================================================
-- Tagesberichte — Schnitt 1: Datenmodell                                  2026-08-04
-- =============================================================================
-- Jeder Mitarbeiter aktivierter Projekte schreibt 1× täglich (Pflicht-Wochentage,
-- bis zur Frist) einen kurzen Bericht im MA-Portal. Ampel im Cockpit:
--   grün = abgegeben ≤ Frist · gelb = abgegeben nach Frist (late) · rot = fehlt.
--
-- Reporting ist die AUSNAHME für Projekte OHNE KPIs (z. B. Fabletics). Aktivierung
-- + Frist + Wochentage + Mindestzeichen liegen JE PROJEKT in app_config
-- 'jsr_daily_reports_cfg' (Standard AUS) — hier NICHT geseedet, der Admin schaltet
-- ein Projekt in Schnitt 2 ein. app_config liest das MA-Portal bereits (APP_CFG).
--
-- `late` wird beim Abschicken EINGEFROREN (nicht später neu gerechnet) → Archiv stabil.
-- Nachreichen: nur der VORTAG (RLS erzwingt report_date in [heute-1, heute], CET-korrekt).
--
-- daily_report_summaries: leere Ablage für die SPÄTERE KI-Zusammenfassung über einen
-- Zeitraum (eigener Schlüssel, serverseitig). JETZT nur die Form, KEINE KI-Anbindung —
-- daily_reports muss dafür später nicht angefasst werden.
--
-- Abhängig von is_admin()/get_my_employee_id()/get_my_employee_project_id()/is_planner().
-- Idempotent. Im Supabase SQL-Editor ausführen.
-- =============================================================================

create extension if not exists pgcrypto;

-- ── Berichte: ein Eintrag je Mitarbeiter und Tag ─────────────────────────────
create table if not exists public.daily_reports (
  id            uuid primary key default gen_random_uuid(),
  employee_id   uuid not null references public.employees(id) on delete cascade,
  project_id    text,                              -- Snapshot beim Abschicken (Archiv bleibt korrekt bei Projektwechsel)
  report_date   date not null,
  body          text not null,
  submitted_at  timestamptz not null default now(),
  late          boolean not null default false,    -- beim Abschicken eingefroren (nach Frist?)
  char_count    int,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (employee_id, report_date)
);
create index if not exists idx_daily_reports_proj_date on public.daily_reports (project_id, report_date);
create index if not exists idx_daily_reports_emp_date  on public.daily_reports (employee_id, report_date);

alter table public.daily_reports enable row level security;

-- Lesen: Admin (Management/HR/Finance) alles · Mitarbeiter eigene · Teamleiter/Projektleiter eigenes Projekt.
drop policy if exists dr_select on public.daily_reports;
create policy dr_select on public.daily_reports
  for select to authenticated
  using (
    public.is_admin()
    or employee_id = public.get_my_employee_id()
    or (public.is_planner() and project_id = public.get_my_employee_project_id())
  );

-- Schreiben: nur der eigene Bericht, nur HEUTE oder VORTAG (CET-korrekt).
drop policy if exists dr_insert on public.daily_reports;
create policy dr_insert on public.daily_reports
  for insert to authenticated
  with check (
    employee_id = public.get_my_employee_id()
    and report_date <=  (now() at time zone 'Europe/Berlin')::date
    and report_date >= ((now() at time zone 'Europe/Berlin')::date - 1)
  );

drop policy if exists dr_update on public.daily_reports;
create policy dr_update on public.daily_reports
  for update to authenticated
  using (
    employee_id = public.get_my_employee_id()
    and report_date >= ((now() at time zone 'Europe/Berlin')::date - 1)
  )
  with check (
    employee_id = public.get_my_employee_id()
    and report_date <=  (now() at time zone 'Europe/Berlin')::date
    and report_date >= ((now() at time zone 'Europe/Berlin')::date - 1)
  );

-- Löschen: nur Admin (Archiv bleibt sonst erhalten).
drop policy if exists dr_delete on public.daily_reports;
create policy dr_delete on public.daily_reports
  for delete to authenticated using ( public.is_admin() );

grant select, insert, update, delete on public.daily_reports to authenticated;

-- ── KI-Zusammenfassung „daneben" (nur Form, KEINE KI in Schnitt 1) ───────────
create table if not exists public.daily_report_summaries (
  id            uuid primary key default gen_random_uuid(),
  project_id    text not null,
  from_date     date not null,
  to_date       date not null,
  summary       text,
  model         text,
  generated_by  uuid references auth.users(id) on delete set null,
  generated_at  timestamptz not null default now()
);
create index if not exists idx_drs_proj on public.daily_report_summaries (project_id, from_date, to_date);

alter table public.daily_report_summaries enable row level security;

drop policy if exists drs_select on public.daily_report_summaries;
create policy drs_select on public.daily_report_summaries
  for select to authenticated using ( public.is_admin() );

drop policy if exists drs_write on public.daily_report_summaries;
create policy drs_write on public.daily_report_summaries
  for all to authenticated using ( public.is_admin() ) with check ( public.is_admin() );

grant select, insert, update, delete on public.daily_report_summaries to authenticated;
