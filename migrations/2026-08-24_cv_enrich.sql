-- Bewerber-Anreicherung per Token-Link (kein zweiter Eingangskanal): HR erzeugt je Bewerber einen Link, der
-- Bewerber ergänzt fehlende Profildaten, die an die BESTEHENDE cvs-Zeile geschrieben werden (kein neuer Eintrag).
-- Muster wie die Terminvereinbarung (Token statt Login). Anlegen = eingeloggte HR (RPC); Lesen/Schreiben durch den
-- Bewerber läuft AUSSCHLIESSLICH über die Edge Function cv-enrich (service role), darum hier keine anon-Policies.

create table if not exists public.cv_enrich_invites (
  token       text primary key default replace(gen_random_uuid()::text,'-',''),
  cv_id       uuid not null references public.cvs(id) on delete cascade,
  created_by  uuid,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '30 days',
  used_at     timestamptz
);
create index if not exists cv_enrich_invites_cv on public.cv_enrich_invites(cv_id);

alter table public.cv_enrich_invites enable row level security;
drop policy if exists cv_enrich_sel on public.cv_enrich_invites;
drop policy if exists cv_enrich_ins on public.cv_enrich_invites;
create policy cv_enrich_sel on public.cv_enrich_invites for select to authenticated using (true);
create policy cv_enrich_ins on public.cv_enrich_invites for insert to authenticated with check (true);
grant select, insert on public.cv_enrich_invites to authenticated;

-- HR (eingeloggt) erzeugt einen Link für einen Bewerber. Gibt den Token zurück.
create or replace function public.create_cv_enrich_invite(p_cv_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_token text;
begin
  insert into cv_enrich_invites(cv_id, created_by) values (p_cv_id, auth.uid())
    returning token into v_token;
  return v_token;
end $$;
grant execute on function public.create_cv_enrich_invite(uuid) to authenticated;
