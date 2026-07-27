-- 2026-07-27  project_profiles entfernen (orphaned)
-- Der Editor „Projekt-übergreifende Rollen" wurde entfernt: das Feld wurde nur editiert
-- und persistiert, aber nirgends für Logik gelesen. Projektleiter laufen über `position`
-- (Organigramm/Kategorie), Mehrfachzuordnung über `project_assignments`. Damit ist die
-- Tabelle nur noch ein Rätsel für später → droppen.
-- Idempotent. Anzuwenden im Supabase SQL-Editor.

drop table if exists public.project_profiles;
