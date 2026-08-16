-- =============================================================================
-- report_forecast — Wochen-Stundenforecast je Projekt/Skill/KW (Schnitt 1)
-- =============================================================================
-- Quelle: Auftraggeber-Datei FC_<Monat>_25Hrs_<SALES|SUPPORT>.xlsx, Blatt 5
-- "Planung+Rueckmeldung KW". Import (Schnitt 2) liest je KW die FC-Stunden.
-- Fuellt die Spalte "Geplant FC" auf Berichtsfolie 3 (StundenTable) - bisher
-- Handeingabe (deck.teams[skill].stunden[].plan).
--
-- Eigene, bericht-spezifische Tabelle wie report_fte. Bewusst NICHT das
-- WFP-Kapazitaetsmodell (forecast_config / Intervalle): andere Granularitaet
-- (KW-Stunden statt Intervall-Calls) und anderer Konsument (Wochenbericht).
--
-- Nur der importierte Auftraggeber-Forecast. Manueller Override + Herkunfts-
-- Anzeige laufen im Bericht ueber deck ...stunden[].psrc (Schnitt 3), daher
-- keine source-Spalte hier. Jahr kommt beim Upload (sicher an der Jahresgrenze,
-- Blatt 5 hat keine Jahresspalte).
--
-- RLS wie report_fte + Projektleiter-Zugang: Management, sonst Planer nur im
-- eigenen Projekt. Idempotent.
-- =============================================================================

create table if not exists public.report_forecast (
  id           uuid primary key default gen_random_uuid(),
  project_id   text not null,
  skill        text not null,
  year         int  not null,
  kw           int  not null,
  fc_hours     numeric,
  file_name    text,
  updated_by   uuid references auth.users(id) on delete set null,
  updated_at   timestamptz not null default now(),
  unique (project_id, skill, year, kw)
);

create index if not exists idx_report_forecast_lookup
  on public.report_forecast(project_id, skill, year, kw);

alter table public.report_forecast enable row level security;

drop policy if exists report_forecast_mgmt on public.report_forecast;
create policy report_forecast_mgmt on public.report_forecast
  for all to authenticated
  using      ( public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()) )
  with check ( public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()) );

grant select, insert, update, delete on public.report_forecast to authenticated;

-- Verifikation (auskommentiert):
-- select column_name from information_schema.columns where table_name='report_forecast';
-- insert into public.report_forecast(project_id,skill,year,kw,fc_hours) values ('<pid>','sales',2026,33,312.5);
-- select * from public.report_forecast where project_id='<pid>' and skill='sales';
