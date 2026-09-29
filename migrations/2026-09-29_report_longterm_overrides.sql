-- Langzeit-Kapazitätsmodell: die vier im Original rot markierten Zeilen (Forecast, Attrition,
-- New Hire FTE, Training Attrition FTE) sollen im System anpassbar sein, ohne dass die
-- importierten Dateiwerte verloren gehen. Deshalb eine eigene Spalte neben rows:
--   overrides = { "<zeilenschluessel>": [12 Werte oder null] }
-- rows bleibt unverändert der Upload. Ein erneuter Import überschreibt rows, nicht overrides.
alter table public.report_longterm add column if not exists overrides jsonb not null default '{}'::jsonb;
comment on column public.report_longterm.overrides is
  'Im Leitstand gesetzte Monatswerte je Zeilenschluessel (nur die anpassbaren Zeilen). Leer/NULL = Wert aus der Datei.';
