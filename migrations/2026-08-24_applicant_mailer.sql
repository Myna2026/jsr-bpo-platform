-- Automatischer Nachrichtenversand an eingehende Bewerber (Kanal-offen, Absender-offen).
-- Kern: EIN Versandprotokoll (applicant_messages) je Bewerber+Kanal+Zweck, plus konfigurierbare Absender
-- (mail_senders, je Marke/Projekt einer). Erster Kanal 'email', erster Zweck 'enrich_invite' (Link zur
-- Anreicherung, Fassung ohne Sprachtest aber mit Schriftprobe). WhatsApp kommt spaeter als zweiter
-- channel-Wert dazu, ohne Strukturbruch. Versand laeuft ueber die Edge Function applicant-mailer.
--
-- WICHTIG: Nichts geht scharf, solange kein Absender active=true mit gesetzter from_email steht UND
-- jsr_enrich_mail_v1.auto_enabled=true ist. Bis dahin: Tabellen/Config existieren, aber es passiert nichts.

begin;

-- ── Absender (je Marke/Projekt einer, nicht fest verdrahtet) ──────────────────
create table if not exists public.mail_senders (
  id          uuid primary key default gen_random_uuid(),
  key         text unique not null,                 -- '25hrs'
  label       text not null,                        -- '25HRS'
  from_email  text not null default '',             -- 'bewerbung@25hrs.de' (steht der User spaeter)
  from_name   text not null default '',             -- '25HRS Recruiting'
  reply_to    text,
  provider    text not null default 'resend',       -- Versanddienst (spaeter erweiterbar)
  active      boolean not null default false,       -- Scharfschaltung dieses Absenders
  seq         int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table public.mail_senders enable row level security;
drop policy if exists mail_senders_sel on public.mail_senders;
drop policy if exists mail_senders_write on public.mail_senders;
create policy mail_senders_sel   on public.mail_senders for select to authenticated using (true);
create policy mail_senders_write on public.mail_senders for all to authenticated using (is_management()) with check (is_management());
grant select, insert, update, delete on public.mail_senders to authenticated;

-- 25HRS als erster Absender, INAKTIV (Adresse traegt der User spaeter nach).
insert into public.mail_senders(key, label, from_name, provider, active, seq)
select '25hrs', '25HRS', '25HRS Recruiting', 'resend', false, 0
where not exists (select 1 from public.mail_senders where key='25hrs');

-- ── Versandprotokoll (kanal-agnostisch: was ging raus, was nicht, auto vs. von Hand) ──
create table if not exists public.applicant_messages (
  id           uuid primary key default gen_random_uuid(),
  cv_id        uuid not null references public.cvs(id) on delete cascade,
  channel      text not null default 'email',        -- email | whatsapp (spaeter)
  purpose      text not null default 'enrich_invite',-- Zweck der Nachricht (erweiterbar)
  origin       text not null,                        -- auto | manual
  sender_key   text,                                 -- welcher mail_senders-Eintrag
  to_address   text,                                 -- Mailadresse (spaeter: Telefonnummer)
  invite_token text,                                 -- mitgeschickter Anreicherungs-Token
  form_id      uuid,                                 -- verwendete Fassung
  status       text not null,                        -- sent | failed | skipped
  error        text,
  provider_id  text,                                 -- Nachrichten-ID des Dienstes
  created_by   uuid,                                 -- bei manuellem Versand: der ausloesende User
  created_at   timestamptz not null default now(),
  sent_at      timestamptz
);
create index if not exists applicant_messages_cv      on public.applicant_messages(cv_id);
create index if not exists applicant_messages_created on public.applicant_messages(created_at desc);
alter table public.applicant_messages enable row level security;
-- Lesen: HR/Management/Planer (fuer die Bewerber-Links-Uebersicht). Schreiben nur die Edge Function
-- (service role umgeht RLS) -> keine authenticated-Insert-Policy noetig.
drop policy if exists applicant_messages_sel on public.applicant_messages;
create policy applicant_messages_sel on public.applicant_messages for select to authenticated
  using ( is_admin() or is_planner() );
grant select on public.applicant_messages to authenticated;

-- ── Automatik-Fassung: Schriftprobe an, Sprachaufnahme (Sprachtest) aus ───────
insert into public.cv_enrich_forms(name, seq, sections)
select 'Automatik: Schriftprobe (ohne Sprachtest)', 100,
  '{"contact":true,"birthday":true,"language":true,"audio":false,"education":true,"experience":true,"availability":true,"writing_sample":true}'::jsonb
where not exists (select 1 from public.cv_enrich_forms where name='Automatik: Schriftprobe (ohne Sprachtest)');

-- ── Steuerungs-Config (Schalter jederzeit umlegbar) ──────────────────────────
-- auto_enabled  : Automatik an/aus (jederzeit umschaltbar; aus = nichts laeuft von selbst, manuell bleibt)
-- trigger_status: ab welchem CV-Status automatisch verschickt wird (Vorschlag: nach erster Sichtung = cv_accepted)
-- sender_key    : welcher Absender (mail_senders.key)
-- form_id       : welche Fassung
-- channel       : erster Kanal
insert into public.app_config(key, value, updated_at)
select 'jsr_enrich_mail_v1',
  jsonb_build_object(
    'auto_enabled', false,
    'trigger_status', 'cv_accepted',
    'sender_key', '25hrs',
    'channel', 'email',
    'form_id', (select id::text from public.cv_enrich_forms where name='Automatik: Schriftprobe (ohne Sprachtest)' limit 1)
  ),
  now()
on conflict (key) do nothing;

commit;
