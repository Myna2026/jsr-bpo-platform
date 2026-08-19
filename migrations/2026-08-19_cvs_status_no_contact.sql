-- Sechste (uebersehene) Absage-Liste: die DB-CHECK-Constraint cvs_status_valid auf public.cvs kannte
-- 'no_contact' nicht. Setzen eines Bewerbers auf "Kein Kontakt moeglich" (STATUS_FLOW reject:true, Symbol 📵)
-- wurde daher von der DB abgelehnt -> Status nie persistiert -> Bewerber blieb in der alten Kanban-Phase.
-- Fix: 'no_contact' in die erlaubten Status aufnehmen (reines Widening, verwirft keine Bestandsdaten).
begin;
alter table public.cvs drop constraint if exists cvs_status_valid;
alter table public.cvs add constraint cvs_status_valid check (status = any (array[
  'cv_inbound','cv_accepted','cv_confirmed','invited','interview','selection1','selection2',
  'contract','training_planned','training','active','inactive','parking',
  'rejected_by_us','rejected_by_employee','rejected_by_client','no_contact','blacklist',
  'terminated_by_us','terminated_by_employee'
]));
commit;
