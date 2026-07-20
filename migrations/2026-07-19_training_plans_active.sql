-- =============================================================================
-- Schulungsplaene: Produktivstart-Spalte                              2026-07-19
-- =============================================================================
-- Etappe FK1 (Teil B): training_plans erhaelt active_date — der Tag, an dem der
-- Batch produktiv/aktiv geht. Wird vom Manager MANUELL bestaetigt (nicht automatisch
-- aus end_date abgeleitet). Ersetzt future_batches.active_date aus jsr_forecast_v1.
--
-- Idempotent (add column if not exists). Anzuwenden im Supabase SQL Editor
-- (hier NICHT ausgefuehrt). Voraussetzung: 2026-07-18_training_plans.sql.
-- =============================================================================

alter table public.training_plans add column if not exists active_date date;


-- =============================================================================
-- Verifikation (auskommentiert)
-- =============================================================================
-- select column_name, data_type from information_schema.columns
--   where table_schema='public' and table_name='training_plans' and column_name='active_date';
--   -- active_date | date
-- =============================================================================
