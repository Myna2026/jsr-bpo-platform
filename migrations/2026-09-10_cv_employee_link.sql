-- Schnitt 1 (Personen-Zeitwahrheit): dauerhafte Verbindung Bewerber <-> Mitarbeiter.
-- Stufe A (leichte Kopplung, NICHT der grosse Personen-Merge): Verweis am Mitarbeiter + Rueckverweis am CV,
-- und der CV wird beim Uebernehmen NICHT mehr geloescht, sondern als 'converted' markiert. Der Recruiting-Verlauf
-- (Mails via mail_messages.cv_id, Termine via interview_invites.cv_id) bleibt damit an der Person haengen.

-- 1) Verweise in beide Richtungen.
alter table public.employees add column if not exists source_cv_id uuid;   -- aus welchem Bewerber der MA entstand
alter table public.cvs       add column if not exists employee_id  uuid;    -- welcher MA aus diesem Bewerber wurde
alter table public.cvs       add column if not exists converted_at timestamptz;
create index if not exists idx_employees_source_cv_id on public.employees(source_cv_id) where source_cv_id is not null;
create index if not exists idx_cvs_employee_id         on public.cvs(employee_id)         where employee_id  is not null;

-- 2) Neuer terminaler CV-Status 'converted' in die versteckte zweite Allow-Liste (cvs_status_valid).
--    (Frontend-STATUS_FLOW ist die erste Allow-Liste; beide muessen den Wert kennen.)
do $$ begin
  if exists (select 1 from pg_constraint where conname='cvs_status_valid' and conrelid='public.cvs'::regclass) then
    alter table public.cvs drop constraint cvs_status_valid;
  end if;
end $$;
alter table public.cvs add constraint cvs_status_valid check (status = any (array[
  'cv_inbound','cv_accepted','cv_confirmed','invited','interview','selection1','selection2','selected',
  'contract','training_planned','training','active','inactive','parking',
  'rejected_by_us','rejected_by_employee','rejected_by_client','no_contact','homeoffice_only','incomplete',
  'blacklist','already_employee','converted','terminated','freigestellt_bezahlt','freigestellt_unbezahlt'
]));

-- 3) Dubletten-Guard NICHT mehr nur beim Anlegen: zusaetzlich BEFORE UPDATE, wenn Telefon oder Mail geaendert wird.
--    Die vorhandene Funktion cvs_guard_employee_dup() bleibt unveraendert: sie greift nur bei frischen Phasen
--    (cv_inbound/cv_accepted/cv_confirmed/invited); 'converted' und terminale Status fallen sauber durch, das
--    Convert-Rueckschreiben (status/employee_id) loest den Guard nicht aus (feuert nur bei phone/email).
drop trigger if exists trg_cvs_guard_employee_dup_upd on public.cvs;
create trigger trg_cvs_guard_employee_dup_upd
  before update of phone, email on public.cvs
  for each row
  when (NEW.phone is distinct from OLD.phone or NEW.email is distinct from OLD.email)
  execute function public.cvs_guard_employee_dup();

notify pgrst, 'reload schema';
