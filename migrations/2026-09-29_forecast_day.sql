-- Tages-Forecast des Auftraggebers. Bisher lasen wir nur das Wochenblatt
-- "Planung + Rueckmeldung KW" ein; laut Auftraggeber (Antwort Edi, 2026-09-29) ist das
-- die falsche Quelle. Gueltig ist Spalte E des Blatts "Tagesplanung":
--   Support "FC in Stunden (Support + Task)", Sales "FC in Stunden (Salestelefonie + Backoffice)".
-- Backoffice und Task zaehlen zur Leistung, deshalb die Summe und nicht nur die Telefonie.
-- Die zugesagten Stunden traegt unsere Seite im Blatt "Rueckmeldung Monatsebene" ein (Spalte G).
create table if not exists public.forecast_day (
  project_id   text not null,
  skill        text not null,
  work_date    date not null,
  fc_total     numeric,          -- Spalte E: Gesamtbedarf des Tages
  fc_main      numeric,          -- Spalte F: Telefonie
  fc_second    numeric,          -- Spalte G: Backoffice bzw. Task
  committed    numeric,          -- unsere Zusage aus "Rueckmeldung Monatsebene"
  file_name    text,
  updated_by   uuid,
  updated_at   timestamptz not null default now(),
  primary key (project_id, skill, work_date)
);

alter table public.forecast_day enable row level security;

drop policy if exists "forecast_day read" on public.forecast_day;
create policy "forecast_day read" on public.forecast_day
  for select using (public.is_planner());

drop policy if exists "forecast_day write" on public.forecast_day;
create policy "forecast_day write" on public.forecast_day
  for all
  using (public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()))
  with check (public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()));

create index if not exists forecast_day_proj_date on public.forecast_day(project_id, skill, work_date);
