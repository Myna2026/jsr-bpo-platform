-- Zwei neue Absage-/Abgangsgruende (reject:true) im STATUS_FLOW: homeoffice_only, incomplete.
-- cvs_status_valid muss mitziehen, sonst lehnt die DB das Setzen still ab (statuscheck faengt den Drift).
alter table public.cvs drop constraint if exists cvs_status_valid;
alter table public.cvs add constraint cvs_status_valid check (status = any (array[
  'cv_inbound','cv_accepted','cv_confirmed','invited','interview','selection1','selection2','selected',
  'contract','training_planned','training','active','inactive','parking',
  'rejected_by_us','rejected_by_employee','rejected_by_client','no_contact','homeoffice_only','incomplete','blacklist',
  'terminated','freigestellt_bezahlt','freigestellt_unbezahlt','terminated_by_us','terminated_by_employee'
]));
