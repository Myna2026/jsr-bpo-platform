-- report_longterm — 12-Monats-Kapazitätsmodell je Projekt/Skill (Langzeitforecast).
-- Quelle: Long_Term_Capacity_25H_Sales_Support.xlsx (Blätter Sales/Support). Zeilen = alle
-- Kennzahlen des Modells (inkl. gerechneter), 12 Monatsspalten ab start_month/start_year.
-- rows = [{label, m:[12 Werte]}] (dieselbe Form wie die Langzeit-Folie). Füllt Berichtsfolie 4.
-- Eigene bericht-spezifische Tabelle wie report_fte/report_forecast. RLS = Management/Planer.
create table if not exists public.report_longterm (
  id           uuid primary key default gen_random_uuid(),
  project_id   text not null,
  skill        text not null,
  start_year   int,
  start_month  int,
  rows         jsonb not null default '[]'::jsonb,
  file_name    text,
  updated_by   uuid references auth.users(id) on delete set null,
  updated_at   timestamptz not null default now(),
  unique (project_id, skill)
);
alter table public.report_longterm enable row level security;
drop policy if exists report_longterm_mgmt on public.report_longterm;
create policy report_longterm_mgmt on public.report_longterm
  for all to authenticated
  using      ( public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()) )
  with check ( public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()) );
grant select, insert, update, delete on public.report_longterm to authenticated;
