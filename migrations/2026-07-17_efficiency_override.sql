-- =============================================================================
-- Forecast: individueller Effizienz-Override pro Mitarbeiter   2026-07-17
-- =============================================================================
-- Ergaenzung zum Forecast-Schema (migrations/2026-07-17_forecast_schema.sql).
-- Erlaubt, die Projekt-/Skill-Effizienz (efficiency_pct) pro MA zu ueberschreiben.
-- RLS unveraendert: employees hat schon RLS -> neue Spalte automatisch abgedeckt.
-- Idempotent (add column if not exists).
--
-- Anzuwenden im Supabase SQL Editor (hier NICHT ausgefuehrt).
-- =============================================================================

alter table public.employees add column if not exists efficiency_override_pct numeric;
-- null = MA erbt den efficiency_pct des Projekts/Skills; gesetzt = individueller Override


-- ---- Verifikation (auskommentiert) -----------------------------------------
-- select column_name, data_type from information_schema.columns
--  where table_schema='public' and table_name='employees'
--    and column_name='efficiency_override_pct';
--   -> 1 Zeile (numeric)
