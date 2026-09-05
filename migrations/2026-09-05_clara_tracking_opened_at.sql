-- Clara-Automatik Schnitt 2: "geöffnet wann" verfolgen.
-- opened_at auf beiden Invite-Tabellen. Gesetzt beim ERSTEN Laden der jeweiligen Seite (JS-getriggert, kein
-- reiner Link-Prefetch). used_at (Anreicherung ausgefüllt) und interview_invites.status/booked_slot (Termin
-- gebucht) existieren bereits.
alter table public.cv_enrich_invites add column if not exists opened_at timestamptz;
alter table public.interview_invites add column if not exists opened_at timestamptz;

-- Öffnungs-Stempel für den Termin-Link (termin.html, öffentlich/anon). Setzt opened_at nur beim ersten Mal.
-- SECURITY DEFINER, weil interview_invites für anon nicht direkt schreibbar ist.
create or replace function public.mark_interview_opened(p_token text)
returns void
language sql
security definer
set search_path to 'public'
as $$
  update public.interview_invites set opened_at = now() where token = p_token and opened_at is null;
$$;
grant execute on function public.mark_interview_opened(text) to anon, authenticated;
