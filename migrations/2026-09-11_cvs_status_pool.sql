-- 'pool'-Status (Clara-Auto-Parken) in die versteckte zweite Allow-Liste cvs_status_valid.
-- Frontend-STATUS_FLOW ist die erste Allow-Liste; beide muessen den Wert kennen.

do $$ begin
  if exists (select 1 from pg_constraint where conname='cvs_status_valid' and conrelid='public.cvs'::regclass) then
    alter table public.cvs drop constraint cvs_status_valid;
  end if;
end $$;
alter table public.cvs add constraint cvs_status_valid check (status = any (array[
  'cv_inbound','cv_accepted','cv_confirmed','invited','interview','selection1','selection2','selected',
  'contract','training_planned','training','active','inactive','parking','pool',
  'rejected_by_us','rejected_by_employee','rejected_by_client','no_contact','homeoffice_only','incomplete',
  'blacklist','already_employee','converted','terminated','freigestellt_bezahlt','freigestellt_unbezahlt'
]));
notify pgrst, 'reload schema';
