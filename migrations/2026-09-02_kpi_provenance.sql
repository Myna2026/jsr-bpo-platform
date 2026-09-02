-- =============================================================================
-- Spur zur Quelle, KPI-Teil / Schnitt 1: Herkunft an die KPI-Werte              2026-09-02
-- =============================================================================
-- Bisher tragen kpi_entries (je Agent) und kpi_project_entries (je Team) nur ein Textflag source='import'|'manual'
-- und entered_by. Damit ist eine importierte KPI-Zahl (Buchungen/AHT/CSAT) NICHT zur Datei/zum Lauf/zur Zeile
-- rückverfolgbar. Wie bei den Stunden (weekly_hours.import_id) ergänzen wir:
--   * import_id  → data_imports(id): welcher Lauf / welche Datei.
--   * source_row → Zeilenindex in der Quelldatei (soweit bekannt).
--   * raw        → Original-Quellzeile (Nachvollzug / Re-Derive).
-- Additiv, ändert nichts Bestehendes. Idempotent.
-- =============================================================================

alter table public.kpi_entries         add column if not exists import_id  uuid references public.data_imports(id) on delete set null;
alter table public.kpi_entries         add column if not exists source_row int;
alter table public.kpi_entries         add column if not exists raw        jsonb;

alter table public.kpi_project_entries add column if not exists import_id  uuid references public.data_imports(id) on delete set null;
alter table public.kpi_project_entries add column if not exists source_row int;
alter table public.kpi_project_entries add column if not exists raw        jsonb;

create index if not exists idx_kpi_entries_import         on public.kpi_entries(import_id);
create index if not exists idx_kpi_project_entries_import on public.kpi_project_entries(import_id);
