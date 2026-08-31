-- Sales-Akquise, Schnitt 0: Fundament + Zugang + Compliance. Start bei NULL (keine Übernahme aus dem Bestand).
-- Absender Moritz Eckstein (moritz.eckstein@25hrs.net), übergabefest. Zugriff nur Rajner/Thorsten/Tive (Freigabeliste,
-- RLS-durchgesetzt). Compliance: Unterdrückungsliste + sales_can_send() + Abmelde-Token je Lead; ohne Prüfung geht
-- (in Schnitt 3) gar nichts raus. Apollo-Anbindung kommt in Schnitt 1 mit EIGENEM Secret SALES_APOLLO_API_KEY.

begin;

-- ── Zugang: nur diese drei (später Moritz) ──
create table if not exists public.sales_access ( user_id uuid primary key, added_at timestamptz not null default now() );
insert into public.sales_access(user_id) values
  ('14a5001c-9efb-4f76-b8f8-145e24b4be5f'),   -- Rajner Gore
  ('b7cbd0b3-961d-41e2-b358-cc13806b3fe3'),   -- Thorsten Schröppe
  ('e9693436-e53e-44a7-b383-a24b8e2bbb99')    -- Tive Master (info@mynaai.de)
on conflict do nothing;

create or replace function public.is_sales_user()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.sales_access where user_id = auth.uid())
$$;
grant execute on function public.is_sales_user() to authenticated;

-- ── Leads (frisch, leer) ──
create table if not exists public.sales_leads (
  id uuid primary key default gen_random_uuid(),
  company text, website text, industry text,
  contact_name text, contact_email text, contact_role text,
  source text check (source in ('mail','list','apollo')),
  status text not null default 'new'
    check (status in ('new','researched','contacted','opened','replied','handover','won','lost','dead','suppressed')),
  research jsonb, hook text, notes text,
  unsub_token uuid not null default gen_random_uuid(),
  next_followup_at timestamptz, last_activity_at timestamptz,
  created_by uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index if not exists sales_leads_unsub_idx on public.sales_leads(unsub_token);
create index if not exists sales_leads_email_idx on public.sales_leads(lower(contact_email));
create index if not exists sales_leads_status_idx on public.sales_leads(status);

-- ── Verlauf/Ereignisse (Dokumentation) ──
create table if not exists public.sales_events (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid references public.sales_leads(id) on delete cascade,
  kind text not null,     -- sent|opened|clicked|replied|followup|handover|unsubscribe|bounce|note|research
  detail jsonb, actor uuid, occurred_at timestamptz not null default now()
);
create index if not exists sales_events_lead_idx on public.sales_events(lead_id, occurred_at);

-- ── Unterdrückungsliste (nie wieder ansprechen) ──
create table if not exists public.sales_suppression (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,     -- immer lower(trim(...)) speichern
  reason text not null,           -- unsubscribe|objection|bounce|manual
  lead_id uuid, created_at timestamptz not null default now()
);

-- ── Standardtext-Vorlagen (von uns formuliert) + KI-Anreicherungs-Schalter ──
create table if not exists public.sales_templates (
  id uuid primary key default gen_random_uuid(),
  key text unique not null, name text, subject text, body text,
  ai_enrich boolean not null default false,   -- aus = nur Standardtext; an = KI personalisiert (keine erfundenen Fakten)
  active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

-- ── Compliance: darf an diese Adresse gesendet werden? (Unterdrückung + Grundprüfung) ──
create or replace function public.sales_can_send(p_email text)
returns boolean language sql stable security definer set search_path=public as $$
  select coalesce(nullif(trim(p_email),''),'') <> ''
     and not exists(select 1 from public.sales_suppression s where s.email = lower(trim(p_email)))
$$;
grant execute on function public.sales_can_send(text) to authenticated, service_role;

-- ── RLS: alle Sales-Tabellen nur für die Freigabeliste (service_role der Edge Functions umgeht) ──
do $$ declare t text;
begin
  foreach t in array array['sales_access','sales_leads','sales_events','sales_suppression','sales_templates'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I_sales on public.%I', t, t);
    execute format('create policy %I_sales on public.%I for all to authenticated using (public.is_sales_user()) with check (public.is_sales_user())', t, t);
  end loop;
end $$;

-- ── Moritz als Agent (Mail-Identität + Persona + Leitplanken). Nicht im Kranz (nicht in AGENT_ORDER). ──
insert into public.ai_agents(key,name,tagline,email,mail_from_name,persona,char_text,focus_text,language_text,
   capabilities,where_keys,outward_facing,decision_authority,guardrails,visibility,active,seq,accent)
values ('moritz','Moritz Eckstein','VP Business Development','moritz.eckstein@25hrs.net','Moritz Eckstein',
  'VP Business Development bei 25HRS. Ansässig in Berlin/München, mehrmals wöchentlich bei Partnern im DACH-Raum, regelmäßig an den Standorten in Kosovo und Albanien. Spricht Entscheider auf Augenhöhe an, knapp und konkret.',
  'Direkt, warm, souverän. Kein Marketing-Sprech, keine Floskeln. Schreibt wie ein Mensch, nicht wie ein System.',
  'Neukontakt im DACH-Raum: Aufmerksamkeit und ein Telefontermin. Angebot: Customer Journey mit Offshore-Standorten im deutschsprachigen Raum.',
  'Deutsch, Sie-Form, kurze Sätze. Immer passend zur Firma und ihrer Branche, nie Einheitsbrei.',
  array[]::text[], array[]::text[], true, '{}'::jsonb,
  jsonb_build_object(
    'no_invented_facts','Nur belegte Firmen-Fakten aus der Recherche; gibt sie nichts her, bleibt es allgemein.',
    'handover','Übergibt an den Menschen, sobald es konkret wird: Termin, Preis, Konditionen, Entscheidung. Verhandelt nie, sagt nie Preise zu. Im Zweifel lieber einmal zu früh übergeben.',
    'compliance','Sendet nur an nicht unterdrückte Adressen; jede Mail trägt Abmeldelink + Impressum; nach Widerspruch nie wieder.'
  ),
  'management', true, 99, '#0f766e')
on conflict (key) do nothing;

-- ── Impressum-Platzhalter (vom User zu füllen; jede Mail hängt es an) ──
insert into public.app_config(key,value)
values ('jsr_sales_impressum_v1', '"25HRS · [Firmierung, Anschrift, Vertretungsberechtigte, Kontakt, Register/USt-IdNr. hier eintragen] · Abmelden: {unsub_link}"'::jsonb)
on conflict (key) do nothing;

commit;
