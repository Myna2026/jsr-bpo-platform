-- 2026-07-24: work_weekend endgültig aus dem Datenmodell entfernt.
-- Das Feld war seit der Verfügbarkeits-Umkehrung (2026-07-23) wirkungslos: die
-- Verfügbarkeit läuft über work_saturday/work_sunday/work_holidays (null=planbar).
-- work_weekend wurde zuvor aus aller Frontend-Logik (Seeds, Init, Import, promote,
-- KI-Planer-Fallback, LOG_LABELS) sowie aus EMP_COLS/EMP_BOOL_COLS entfernt.
-- Diese Migration dokumentiert das bereits manuell per SQL ausgeführte Droppen der Spalte.
alter table public.employees drop column if exists work_weekend;
