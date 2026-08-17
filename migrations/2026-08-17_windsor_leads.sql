-- Meta-Bewerbungen (facebook_leads) — Schnitt 1: Staging-Tabelle.
-- Ein zweiter Windsor-Auftrag schreibt taeglich hierhin (Service-Key, an RLS vorbei).
-- lead_id = Meta LeadGenInfo "id" (stabil) = Idempotenz-Schluessel -> Upsert, nie doppelt.
-- raw = kompletter Rohsatz (nichts geht verloren). Der Import-Runner (Schnitt 2) liest
-- imported=false, legt cvs an (source='meta'), setzt imported/imported_cv_id bzw.
-- status_review='dup' bei Telefon-Kollision. Zugriff: HR + Management (is_admin()).

create table if not exists public.windsor_leads (
  lead_id        text primary key,
  full_name      text,
  phone          text,
  german         text,
  cc_experience  text,
  work_time      text,
  available      text,
  interests      text,
  created_time   timestamptz,
  campaign       text,
  ad_name        text,
  form_id        text,
  raw            jsonb,
  imported       boolean not null default false,
  imported_cv_id uuid,
  status_review  text,          -- null | 'dup' | 'discarded'
  inserted_at    timestamptz not null default now()
);

create index if not exists idx_windsor_leads_pending
  on public.windsor_leads(inserted_at) where imported = false;

alter table public.windsor_leads enable row level security;

drop policy if exists windsor_leads_sel on public.windsor_leads;
create policy windsor_leads_sel on public.windsor_leads for select to authenticated
  using ( public.is_admin() );
drop policy if exists windsor_leads_ins on public.windsor_leads;
create policy windsor_leads_ins on public.windsor_leads for insert to authenticated
  with check ( public.is_admin() );
drop policy if exists windsor_leads_upd on public.windsor_leads;
create policy windsor_leads_upd on public.windsor_leads for update to authenticated
  using ( public.is_admin() ) with check ( public.is_admin() );
drop policy if exists windsor_leads_del on public.windsor_leads;
create policy windsor_leads_del on public.windsor_leads for delete to authenticated
  using ( public.is_admin() );

grant select, insert, update, delete on public.windsor_leads to authenticated;
