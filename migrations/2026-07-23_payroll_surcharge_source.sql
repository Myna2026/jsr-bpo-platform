-- =============================================================================
-- Zuschläge Weg A: payroll_inputs erweitern                            2026-07-23
-- =============================================================================
-- Zweck (Zuschlags-Automatik aus shift_assignments):
--   * total_worked_hours  — bisher NUR im Modal erfasst, aber NIE persistiert.
--                           Ohne diese Spalte gehen die (auto- oder manuell
--                           gesetzten) gearbeiteten Stunden bei jedem Reload
--                           verloren -> Überstunden fielen auf 0 zurück.
--   * surcharge_source     — Herkunft der Zuschlagsstunden pro MA/Monat:
--                           'auto'    = aus Schichtplan klassifiziert
--                           'manuell' = vom Management überschrieben
--                           NULL      = noch nicht gepflegt
--
-- Additiv & idempotent. Im Supabase SQL Editor anwenden (hier NICHT ausgeführt).
-- Voraussetzung: 2026-07-19_payroll_inputs.sql
-- =============================================================================

alter table public.payroll_inputs
  add column if not exists total_worked_hours numeric,
  add column if not exists surcharge_source   text;
