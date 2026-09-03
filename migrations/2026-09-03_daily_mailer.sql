-- Mailer-Tagesumbau, Schnitt 1: feinste Ebene speichern. Der Kunde rechnet Mails/h JE TAG (SUMPRODUCT über
-- Name Genesys × Datum × Bearbeiter='ME' × Gesamt_bearbeitet ÷ LogTime), wir bisher je ISO-Woche. Beide Mailer-
-- Quellblätter haben eine Datumsspalte → tagesgenau. daily_mailer hält die Rohwerte je (Projekt, MA, Tag):
-- mails = Σ Gesamt_bearbeitet (Bearbeiter=ME), log_hours = LogTime ME. Mails/h wird beim Lesen abgeleitet
-- (Register-Prinzip, wie daily_hours). Kein Verdichten mehr. Idempotent.
create table if not exists public.daily_mailer (
  id           uuid primary key default gen_random_uuid(),
  import_id    uuid references public.data_imports(id) on delete set null,
  project_id   text not null,
  employee_id  uuid not null references public.employees(id) on delete cascade,
  work_date    date not null,
  mails        numeric,
  log_hours    numeric,
  raw          jsonb,
  created_at   timestamptz not null default now()
);
create unique index if not exists uq_daily_mailer on public.daily_mailer(project_id, employee_id, work_date);
create index if not exists idx_daily_mailer_scope on public.daily_mailer(project_id, work_date);

-- RLS wie kpi_entries (Mails/h ist eine KPI): perm-Bereich 'kpi', Projekt-Scope. Lesen ab mode<>none, schreiben edit.
alter table public.daily_mailer enable row level security;
drop policy if exists dm_perm_select on public.daily_mailer;
create policy dm_perm_select on public.daily_mailer for select to authenticated
  using ( public.perm_mode(auth.uid(),'kpi') <> 'none' and public.perm_proj_ok(auth.uid(),'kpi', project_id, null) );
drop policy if exists dm_perm_write on public.daily_mailer;
create policy dm_perm_write on public.daily_mailer for all to authenticated
  using ( public.perm_mode(auth.uid(),'kpi') = 'edit' and public.perm_proj_ok(auth.uid(),'kpi', project_id, null) )
  with check ( public.perm_mode(auth.uid(),'kpi') = 'edit' and public.perm_proj_ok(auth.uid(),'kpi', project_id, null) );
grant select, insert, update, delete on public.daily_mailer to authenticated;
grant select on public.daily_mailer to agent_ro;
