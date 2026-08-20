-- cvs_status_valid lief gegen STATUS_FLOW auseinander (wie vorher bei no_contact): die Kündigung setzt
-- 'terminated' bzw. 'freigestellt_bezahlt'/'freigestellt_unbezahlt', keiner davon war erlaubt -> Update still
-- abgelehnt (Herolind Syla hing auf 'training'). Fix: Constraint = voller STATUS_FLOW-Satz PLUS die kanonischen
-- terminated_by_* (CLAUDE.md-Modell, legacy-sicher). Reines Widening, verwirft keine Bestandsdaten.
begin;
alter table public.cvs drop constraint if exists cvs_status_valid;
alter table public.cvs add constraint cvs_status_valid check (status = any (array[
  -- CV-Funnel
  'cv_inbound','cv_accepted','cv_confirmed','invited','interview','selection1','selection2','selected',
  -- Mitarbeiter-Phasen
  'contract','training_planned','training','active','inactive',
  -- Sonderfall
  'parking',
  -- Absagen / Abgänge
  'rejected_by_us','rejected_by_employee','rejected_by_client','no_contact','blacklist',
  -- Kündigung / Offboarding (STATUS_FLOW nutzt 'terminated' + freigestellt_*; terminated_by_* bleibt erlaubt)
  'terminated','freigestellt_bezahlt','freigestellt_unbezahlt','terminated_by_us','terminated_by_employee'
]));
commit;
