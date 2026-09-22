-- Wer bereits übernommen ist (oder als Mitarbeiter geführt wird), darf nie wieder als NEUER Bewerber angelegt werden,
-- egal aus welcher Quelle (Google-Sheet-Import, Meta, Vor-Ort-Tablet, HR-Formular, API).
-- Vorgeschichte 22.09.2026: fünf Mitarbeiter (1074-1080) wurden aus Bewerbungen angelegt, die dabei noch gelöscht wurden;
-- der Sheet-Import spielte dieselben Zeilen danach wieder ein. Der Dubletten-Wächter fing sie als „Bereits Mitarbeiter“,
-- die Bewerbung stand aber doppelt im System. Jetzt: solche Neuanlagen werden gar nicht erst angelegt.
create or replace function public.cvs_guard_employee_dup()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_cph text; v_cem text; m record; v_old record;
begin
  v_cph := nullif(regexp_replace(coalesce(NEW.phone,''),'\D','','g'),'');
  v_cem := nullif(lower(trim(coalesce(NEW.email,''))),'');

  -- (1) NEUANLAGE einer Person, die schon als übernommene Bewerbung im System steht: gar nicht anlegen.
  --     Die bestehende Bewerbung ist die Wahrheit (mit Verlauf und Mitarbeiter-Verknüpfung).
  if TG_OP = 'INSERT' and (v_cph is not null or v_cem is not null) then
    select c.id, c.employee_id, trim(coalesce(c.first_name,'')||' '||coalesce(c.last_name,'')) nm into v_old
      from public.cvs c
     where c.status in ('converted','already_employee')
       and ( (v_cem is not null and lower(trim(coalesce(c.email,''))) = v_cem)
          or (v_cph is not null and nullif(regexp_replace(coalesce(c.phone,''),'\D','','g'),'') = v_cph) )
     limit 1;
    if found then
      raise exception 'Bewerber % ist bereits übernommen (Bewerbung %). Neuanlage abgelehnt, bitte die bestehende Bewerbung verwenden.', coalesce(v_old.nm,'(unbekannt)'), v_old.id
        using errcode = '23505';
    end if;
  end if;

  -- (2) wie bisher: frische Bewerbung, die auf einen Mitarbeiter trifft → zurückhalten statt anrufen
  if NEW.status is null or NEW.status not in ('cv_inbound','cv_accepted','cv_confirmed','invited') then
    return NEW;
  end if;
  if v_cph is null and v_cem is null then return NEW; end if;
  select e.id, e.staff_number, trim(coalesce(e.first_name,'')||' '||coalesce(e.last_name,'')) nm, e.status,
         case when v_cem is not null and lower(trim(coalesce(e.email,'')))=v_cem then 'Mail'
              when v_cph is not null and nullif(regexp_replace(coalesce(e.phone,''),'\D','','g'),'')=v_cph then 'Telefon' end treffer
    into m
  from public.employees e
  where (v_cem is not null and lower(trim(coalesce(e.email,'')))=v_cem)
     or (v_cph is not null and nullif(regexp_replace(coalesce(e.phone,''),'\D','','g'),'')=v_cph)
  order by (case when v_cem is not null and lower(trim(coalesce(e.email,'')))=v_cem then 0 else 1 end)
  limit 1;
  if found then
    NEW.status := 'already_employee';
    NEW.extra := coalesce(NEW.extra,'{}'::jsonb) || jsonb_build_object('employee_match',
      jsonb_build_object('employee_id', m.id, 'staff_number', m.staff_number, 'name', m.nm, 'ma_status', m.status, 'treffer', m.treffer, 'held_at', now()));
  end if;
  return NEW;
end $$;
