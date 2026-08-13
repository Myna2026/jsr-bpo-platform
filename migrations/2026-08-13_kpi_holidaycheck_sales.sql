-- =============================================================================
-- KPIs HolidayCheck · Sales (manuelle Eingabe je Mitarbeiter)                 2026-08-13
-- =============================================================================
-- Ergänzt drei fehlende Basis-Kennzahlen (reine Zählwerte, Typ 'number'):
--   Offene Buchungen · OSL-Buchungen · Sales Calls
-- Projektbezogen (project_id = HolidayCheck, skill = 'sales') — gilt NICHT global.
-- thresholds = [] → keine Ampel (reine Zahl). Zielwerte später im KPI-Editor ergänzbar.
--
-- Abgeleitete Kennzahlen (Buchungen gesamt, Anteil OSL) sind hier BEWUSST NICHT enthalten:
-- das System kennt keine Formel-KPIs — Umsetzung folgt separat (nicht als Handrechnung).
--
-- Idempotent (upsert per Slug). Im Supabase SQL-Editor ausführen.
-- =============================================================================
do $$
declare pid text;
begin
  select id into pid from public.projects where lower(name) = 'holidaycheck' limit 1;
  if pid is null then select id into pid from public.projects where name ilike '%holidaycheck%' limit 1; end if;
  if pid is null then raise exception 'HolidayCheck-Projekt nicht gefunden — bitte Projektnamen prüfen.'; end if;

  insert into public.kpi_config (id, project_id, skill, name, type, unit, thresholds) values
    ('kpi_hc_open_bookings', pid, 'sales', 'Offene Buchungen', 'number', '', '[]'::jsonb),
    ('kpi_hc_osl',           pid, 'sales', 'OSL-Buchungen',    'number', '', '[]'::jsonb),
    ('kpi_hc_sales_calls',   pid, 'sales', 'Sales Calls',      'number', '', '[]'::jsonb)
  on conflict (id) do update
    set project_id=excluded.project_id, skill=excluded.skill, name=excluded.name,
        type=excluded.type, unit=excluded.unit;   -- thresholds NICHT überschreiben (spätere Editor-Pflege bleibt)

  raise notice 'HolidayCheck Sales KPIs angelegt: Offene Buchungen, OSL-Buchungen, Sales Calls (Projekt %).', pid;
end $$;
