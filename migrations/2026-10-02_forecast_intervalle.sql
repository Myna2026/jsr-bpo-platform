-- Intervallplanung des Auftraggebers: je Tag und Halbstunde der Telefoniebedarf.
-- Quelle ist das Blatt "Intervallplanung" der Forecast-Datei, Spalte D "Stunden im Intervall".
-- Wichtig zur Einordnung (geprueft 2026-10-02): die Summe aller Intervalle eines Tages ergibt exakt
-- den Telefonie-Forecast des Tagesblatts (forecast_day.fc_main), NICHT den Gesamtbedarf. Aufgaben und
-- Mail stehen nur im Tagesblatt (fc_second) und haben kein Intervallprofil.
-- bedarf_h ist eine Menge in Stunden INNERHALB der halben Stunde. Als Besetzung gelesen sind das
-- bedarf_h / 0,5 Personen gleichzeitig; Stundenwerte entstehen durch Mittelung der Besetzung, der
-- Tagesbedarf dagegen durch Summe der Stunden. Beides nie vermischen.
create table if not exists forecast_interval (
  project_id text not null,
  skill      text not null,
  work_date  date not null,
  slot       time not null,
  bedarf_h   numeric(8,5) not null,
  calls      numeric(10,4),
  file_name  text,
  updated_by uuid,
  updated_at timestamptz not null default now(),
  primary key (project_id, skill, work_date, slot)
);
create index if not exists forecast_interval_tag on forecast_interval(project_id, work_date);

alter table forecast_interval enable row level security;
drop policy if exists "forecast_interval read" on forecast_interval;
create policy "forecast_interval read" on forecast_interval for select using (is_planner());
drop policy if exists "forecast_interval write" on forecast_interval;
create policy "forecast_interval write" on forecast_interval for all
  using (is_management() or (is_planner() and project_id = get_my_employee_project_id()))
  with check (is_management() or (is_planner() and project_id = get_my_employee_project_id()));
