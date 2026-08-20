-- Promotete Sammelfeld-Felder zu echten Spalten:
--  * cvs.contract (jsonb): wird beim Übernehmen geprüft (hinterlegter Vertrag) -> aus dem extra-Sink gelesen
--    ist fragil. employees.contract existiert bereits als Spalte.
--  * status_changed_at (timestamptz): Zeitstempel des Phasenwechsels. BUG: geschrieben als 'status_changed',
--    gelesen als 'last_status_change' -> matchte nie, "Zeit in Phase"/">7 Tage" fielen still auf cv_date zurück.
--    Jetzt eine Spalte + einheitlicher Name (Frontend zieht mit). Auf cvs UND employees (Kanban schreibt beide).
begin;
-- cvs
alter table public.cvs add column if not exists contract jsonb;
alter table public.cvs add column if not exists status_changed_at timestamptz;
update public.cvs set contract = extra->'contract'
  where extra ? 'contract' and contract is null;
update public.cvs set status_changed_at = (extra->>'status_changed')::timestamptz
  where extra ? 'status_changed' and status_changed_at is null;
update public.cvs set extra = extra - 'contract' - 'status_changed' - 'type'
  where extra ?| array['contract','status_changed','type'];
-- employees (contract-Spalte existiert schon)
alter table public.employees add column if not exists status_changed_at timestamptz;
update public.employees set status_changed_at = (extra->>'status_changed')::timestamptz
  where extra ? 'status_changed' and status_changed_at is null;
update public.employees set extra = extra - 'status_changed'
  where extra ? 'status_changed';
commit;
