-- Rueckmeldung auf Monatsebene aus der Auftraggeber-Datei: je Tag und Skill der Forecast, die vom
-- Auftraggeber gezaehlten geleisteten Stunden und die Spalte "Vergutet". Letztere ist NICHT die
-- Zahlung, sondern die Obergrenze: Forecast plus angeforderte Zusatzstunden (nachgewiesen am
-- Juniblatt 2026, die Differenz ist an 8 von 10 Tagen eine glatte Stundenzahl). Gezahlt wird der
-- kleinere Wert aus Obergrenze und geleistet.
-- Wozu die Tabelle: sie ist die Gegenprobe zu unserer eigenen Rechnung. Die Spalten gibt es nicht in
-- jeder Datei (in den Septemberdateien fehlen sie), der Import nimmt sie nur mit, wenn sie da sind.
create table if not exists hc_month_feedback (
  project_id   text not null,
  skill        text not null,
  work_date    date not null,
  fc_hours        numeric(8,3),
  delivered_hours numeric(8,3),
  ceiling_hours   numeric(8,3),
  file_name    text,
  updated_by   uuid,
  updated_at   timestamptz not null default now(),
  primary key (project_id, skill, work_date)
);

alter table hc_month_feedback enable row level security;
drop policy if exists "hc_month_feedback read" on hc_month_feedback;
create policy "hc_month_feedback read" on hc_month_feedback for select using (is_planner());
drop policy if exists "hc_month_feedback write" on hc_month_feedback;
create policy "hc_month_feedback write" on hc_month_feedback for all
  using (is_management() or (is_planner() and project_id = get_my_employee_project_id()))
  with check (is_management() or (is_planner() and project_id = get_my_employee_project_id()));
