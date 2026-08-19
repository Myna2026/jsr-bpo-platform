-- Problem: Windsor schreibt windsor_leads per delete+insert (voller Tabellen-Neuaufbau, alle Zeilen gleicher
-- inserted_at) und setzt damit jede Nacht unsere Verwaltungsspalten (imported, imported_cv_id, status_review)
-- auf die Defaults zurueck -> manuelle Uebernahmen + Dubletten-Entscheidungen gehen verloren, Gefahr von
-- Doppel-Anlagen. Loesung: persistente Schatten-Tabelle, die Windsor nie anfasst, + zwei Trigger auf
-- windsor_leads (BEFORE INSERT stellt den Status wieder her, AFTER UPDATE persistiert jede Aenderung).
-- App-Code (Edge Function + Browser) bleibt unveraendert: er liest/schreibt weiter windsor_leads.

create table if not exists public.lead_import_state (
  lead_id        text primary key,
  imported       boolean not null default false,
  imported_cv_id uuid,
  status_review  text,
  updated_at     timestamptz not null default now()
);

alter table public.lead_import_state enable row level security;
drop policy if exists lead_import_state_rw on public.lead_import_state;
create policy lead_import_state_rw on public.lead_import_state for all to authenticated
  using ( public.is_admin() ) with check ( public.is_admin() );
grant select, insert, update, delete on public.lead_import_state to authenticated;

-- Backfill: die bereits uebernommenen Bewerbungen exakt aus cvs.extra.lead_id (jede Meta-cv traegt ihre Lead-ID).
insert into public.lead_import_state (lead_id, imported, imported_cv_id, status_review)
select c.extra->>'lead_id', true, c.id, null
from public.cvs c
where c.source='meta' and c.extra->>'lead_id' is not null
on conflict (lead_id) do update
  set imported = excluded.imported, imported_cv_id = excluded.imported_cv_id, updated_at = now();

-- AFTER UPDATE: jede Statusaenderung an windsor_leads dauerhaft in die Schatten-Tabelle spiegeln.
create or replace function public.lead_state_persist() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if NEW.imported is distinct from OLD.imported
     or NEW.imported_cv_id is distinct from OLD.imported_cv_id
     or NEW.status_review is distinct from OLD.status_review then
    insert into public.lead_import_state (lead_id, imported, imported_cv_id, status_review, updated_at)
    values (NEW.id, coalesce(NEW.imported,false), NEW.imported_cv_id, NEW.status_review, now())
    on conflict (lead_id) do update
      set imported = excluded.imported, imported_cv_id = excluded.imported_cv_id,
          status_review = excluded.status_review, updated_at = now();
  end if;
  return NEW;
end $$;
drop trigger if exists trg_lead_state_persist on public.windsor_leads;
create trigger trg_lead_state_persist after update on public.windsor_leads
  for each row execute function public.lead_state_persist();

-- BEFORE INSERT: beim Windsor-Neuaufbau den gemerkten Status zuruecklegen (statt Default false/null).
create or replace function public.lead_state_restore() returns trigger
language plpgsql security definer set search_path = public as $$
declare s public.lead_import_state%rowtype;
begin
  select * into s from public.lead_import_state where lead_id = NEW.id;
  if found then
    NEW.imported       := coalesce(s.imported, false);
    NEW.imported_cv_id := s.imported_cv_id;
    NEW.status_review  := s.status_review;
  end if;
  return NEW;
end $$;
drop trigger if exists trg_lead_state_restore on public.windsor_leads;
create trigger trg_lead_state_restore before insert on public.windsor_leads
  for each row execute function public.lead_state_restore();

-- Sofort-Sync: die aktuell (heute Nacht neu angelegten) windsor_leads-Zeilen aus der Schatten-Tabelle korrigieren.
update public.windsor_leads w
set imported = s.imported, imported_cv_id = s.imported_cv_id, status_review = s.status_review
from public.lead_import_state s
where s.lead_id = w.id
  and ( w.imported is distinct from s.imported
        or w.imported_cv_id is distinct from s.imported_cv_id
        or w.status_review is distinct from s.status_review );
