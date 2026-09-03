-- Kanban-Neudefinition auf 8 Phasen (verlustfrei). Nur zwei Paare werden zusammengeführt, damit je Phase
-- EINE Spalte entsteht; alle anderen Status behalten ihren Key (nur STATUS_FLOW-Labels/Spalten ändern sich).
--   Phase 2 Terminvereinbarung:  cv_accepted  -> cv_confirmed
--   Phase 4 Interview im Büro:    selection1   -> interview
-- Ausgänge (no_contact/rejected_*/parking/blacklist/homeoffice_only/incomplete) und Nicht-Bewerber
-- (already_employee/terminated) bleiben unverändert.
update public.cvs set status='cv_confirmed', updated_at=now() where status='cv_accepted';
update public.cvs set status='interview',    updated_at=now() where status='selection1';
