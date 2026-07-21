-- =============================================================================
-- Schichtplanung: verlustfreie Zelle  (Nachtrag zu Etappe 2)          2026-07-21
-- =============================================================================
-- Die Schicht-Zelle im Frontend (s_<emp>_<ds>) enthält mehr Felder als die
-- getippten Spalten abbilden: isSplit, split_morning/afternoon, partial_absence,
-- partial_end, absence_type u. a. Damit ein aus der DB geladener Plan EXAKT
-- dasselbe Ergebnis liefert wie vorher (Stunden, Netto, Split, Teil-Abwesenheit,
-- Intraday-Raster), speichern wir das komplette Zellen-Objekt verlustfrei als
-- jsonb und rekonstruieren es 1:1.
--
-- Die getippten Spalten (label, shift_value, net_hours, …) bleiben als
-- denormalisierte Kopie für spätere SQL-Auswertungen/Payroll erhalten, werden
-- aber NICHT für die Rekonstruktion gelesen. Quelle der Wahrheit fürs Frontend
-- ist 'shift' (+ 'slots').
--
-- Reine Speicher-Erweiterung, keine Logik. Idempotent (add column if not exists).
-- VOR dem Etappe-3-Frontend-Deploy einspielen.
-- =============================================================================

alter table public.shift_assignments
  add column if not exists shift jsonb;
