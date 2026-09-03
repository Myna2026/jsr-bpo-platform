-- Verhinderung von Übernahme-Dubletten an EINEM Chokepoint für ALLE Bewerber-Entstehungswege (Google-Sheet-Sync,
-- Meta-Runner, GDoc-Bulk, manuelles Formular, applicant-import Edge Function, vor-Ort-Tablet): ein BEFORE INSERT
-- Trigger auf cvs. Trifft das normalisierte Telefon ODER die Mail einen bestehenden Mitarbeiter, wird der neue
-- Bewerber NICHT als normaler Trichter-Eintrag angelegt, sondern auf status='already_employee' gesetzt und mit dem
-- Treffer markiert (extra.employee_match). So sieht HR die Wiederbewerbung im Dubletten-Bereich, aber Deonita ruft
-- niemanden an, der schon Mitarbeiter (oder Ex-Mitarbeiter) ist. Idempotent.

-- 1) Status in der cvs-CHECK-Constraint erlauben (versteckte zweite Allow-Liste).
do $$ begin
  if exists (select 1 from pg_constraint where conname='cvs_status_valid' and conrelid='public.cvs'::regclass) then
    alter table public.cvs drop constraint cvs_status_valid;
  end if;
end $$;
alter table public.cvs add constraint cvs_status_valid check (status = any (array[
  'cv_inbound','cv_accepted','cv_confirmed','invited','interview','selection1','selection2','selected',
  'contract','training_planned','training','active','inactive','parking',
  'rejected_by_us','rejected_by_employee','rejected_by_client','no_contact','homeoffice_only','incomplete',
  'blacklist','already_employee','terminated','freigestellt_bezahlt','freigestellt_unbezahlt'
]));

-- 2) Trigger-Funktion: Mitarbeiter-Treffer über Telefon (nur Ziffern) ODER Mail (lower/trim).
create or replace function public.cvs_guard_employee_dup()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_cph text; v_cem text; m record;
begin
  -- nur bei „frischen" Bewerbungen prüfen (kein Rückschreiben, keine bereits markierten Dubletten)
  if NEW.status is null or NEW.status not in ('cv_inbound','cv_accepted','cv_confirmed','invited') then
    return NEW;
  end if;
  v_cph := nullif(regexp_replace(coalesce(NEW.phone,''),'\D','','g'),'');
  v_cem := nullif(lower(trim(coalesce(NEW.email,''))),'');
  if v_cph is null and v_cem is null then return NEW; end if;
  select e.id, e.staff_number, trim(coalesce(e.first_name,'')||' '||coalesce(e.last_name,'')) nm, e.status,
         case when v_cem is not null and lower(trim(coalesce(e.email,'')))=v_cem then 'Mail'
              when v_cph is not null and nullif(regexp_replace(coalesce(e.phone,''),'\D','','g'),'')=v_cph then 'Telefon' end treffer
    into m
  from public.employees e
  where (v_cem is not null and lower(trim(coalesce(e.email,'')))=v_cem)
     or (v_cph is not null and nullif(regexp_replace(coalesce(e.phone,''),'\D','','g'),'')=v_cph)
  order by (case when v_cem is not null and lower(trim(coalesce(e.email,'')))=v_cem then 0 else 1 end)  -- Mail-Treffer bevorzugt
  limit 1;
  if found then
    NEW.status := 'already_employee';
    NEW.extra := coalesce(NEW.extra,'{}'::jsonb) || jsonb_build_object('employee_match',
      jsonb_build_object('employee_id', m.id, 'staff_number', m.staff_number, 'name', m.nm, 'ma_status', m.status, 'treffer', m.treffer, 'held_at', now()));
  end if;
  return NEW;
end $$;

drop trigger if exists trg_cvs_guard_employee_dup on public.cvs;
create trigger trg_cvs_guard_employee_dup before insert on public.cvs
  for each row execute function public.cvs_guard_employee_dup();
