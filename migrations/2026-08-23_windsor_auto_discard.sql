-- Auto-Verwerfen hinfaelliger Wiederholungsbewerbungen. Steht der kollidierende Bestand bereits auf einem
-- terminalen Absage-Status (blacklist / no_contact / rejected_by_us / rejected_by_employee), ist die neue Meta-
-- Bewerbung ohnehin hinfaellig -> status_review='auto_discarded' statt 'dup'. Zur MANUELLEN Entscheidung bleiben
-- nur Kollisionen mit noch aktivem Bestand (dort koennte die neue Bewerbung aktuellere Angaben tragen).
--
-- Die Regel lebt als TRIGGER (EINE Wahrheit) statt dupliziert in Browser-Runner + Edge Function + Backlog:
-- sie greift fuer JEDEN Schreiber und heilt sich beim naechtlichen Windsor-Neuschreib selbst (Bestand, der spaeter
-- terminal wird, wird beim Re-Insert neu bewertet). Bewusst NUR diese vier Status (nicht alle REJECT_STATUS_KEYS):
-- rejected_by_client / homeoffice_only / incomplete koennen wieder relevant werden -> bleiben in der Entscheidung.

create or replace function public.windsor_leads_auto_discard()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if NEW.status_review = 'dup' and NEW.imported_cv_id is not null then
    if exists (
      select 1 from public.cvs c
       where c.id = NEW.imported_cv_id
         and c.status in ('blacklist','no_contact','rejected_by_us','rejected_by_employee')
    ) then
      NEW.status_review := 'auto_discarded';
    end if;
  end if;
  return NEW;
end $$;

-- Nach lead_state_restore (Namen: trg_l... < trg_w..., BEFORE-Trigger feuern alphabetisch) -> imported_cv_id und
-- status_review sind beim Re-Insert bereits gesetzt, dann bewertet dieser Trigger neu.
drop trigger if exists trg_windsor_auto_discard on public.windsor_leads;
create trigger trg_windsor_auto_discard
  before insert or update of status_review on public.windsor_leads
  for each row execute function public.windsor_leads_auto_discard();

-- Backlog: bestehende offene Dubletten mit terminalem Bestand einmalig auto-verwerfen (feuert Persist-Trigger ->
-- landet dauerhaft in lead_import_state, uebersteht den Neuschreib).
update public.windsor_leads w
   set status_review = 'auto_discarded'
  from public.cvs c
 where w.status_review = 'dup'
   and w.imported_cv_id = c.id
   and c.status in ('blacklist','no_contact','rejected_by_us','rejected_by_employee');
