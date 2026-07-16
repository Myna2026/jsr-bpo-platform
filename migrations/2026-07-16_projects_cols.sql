-- =============================================================================
-- Projekte: fehlende Modal-Felder als Spalten nachziehen   2026-07-16
-- =============================================================================
-- Ergaenzung zu migrations/2026-07-16_projects.sql. Das Projekt-Edit-Modal
-- pflegt Felder, die im urspruenglichen Schema fehlten -> sonst Datenverlust
-- beim DB-Save (Etappe 3). Idempotent (add column if not exists).
--
-- RLS unveraendert: die read-internal/HR-write-Policies gelten tabellenweit,
-- neue Spalten sind automatisch abgedeckt.
--
-- Anzuwenden im Supabase SQL Editor (hier NICHT ausgefuehrt).
-- =============================================================================

alter table public.projects add column if not exists contract_start          text;
alter table public.projects add column if not exists contract_end            text;
alter table public.projects add column if not exists language_requirement    text;
alter table public.projects add column if not exists description             text;
alter table public.projects add column if not exists monthly_hours_per_agent numeric;


-- ---- Verifikation (auskommentiert) -----------------------------------------
-- select column_name, data_type from information_schema.columns
--  where table_schema='public' and table_name='projects'
--    and column_name in ('contract_start','contract_end','language_requirement',
--                        'description','monthly_hours_per_agent')
--  order by column_name;
--   -> 5 Zeilen (4x text, monthly_hours_per_agent numeric)
