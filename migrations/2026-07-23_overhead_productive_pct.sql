-- =============================================================================
-- Overhead sauber isolieren: produktiver Anteil pro MA                 2026-07-23
-- =============================================================================
-- Zweck: Overhead-MA (Projektleiter, Trainer, Teamleiter, QM, Supervisor, Coach,
--   Ansprechpartner) liefern i.d.R. keine abrechenbaren Stunden. Sie sollen im
--   Forecast/Wirtschaftlichkeit/Produktivitaet standardmaessig KEINEN Umsatz
--   erzeugen. Kann anteilig produktiv sein (z.B. Teamleiter 30%).
--
--   overhead_productive_pct: 0-100. Anteil der Produktivstunden, der Umsatz
--   erzeugt. DEFAULT 0 -> Overhead erzeugt standardmaessig keinen Umsatz.
--   Agenten sind von der Overhead-Erkennung nicht betroffen (immer 100%).
--
-- Kosten bleiben unveraendert (Overhead kostet voll).
--
-- Additiv & idempotent. Im Supabase SQL Editor anwenden (hier NICHT ausgefuehrt).
-- =============================================================================

alter table public.employees
  add column if not exists overhead_productive_pct numeric default 0;
