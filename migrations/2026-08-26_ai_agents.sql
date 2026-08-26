-- KI-Agenten mit Namen und Gesicht. EIN Register als Wahrheit; alles andere (Vorstellungs-Bereich,
-- Präsenz in den Modulen, Nutzungs-Zusammenfassung) rendert daraus. Erweiterbar: weitere Agenten = neue Zeile.
-- Zwei Pflicht-Dinge sind hier fest verankert:
--   disclosure         = Außen-Kennzeichnung ("digitale Assistentin bei 25HRS"), damit erkennbar ist, dass
--                        z. B. Clara keine Person ist. Pflicht bei outward_facing=true.
--   decision_authority = was der Agent entscheiden darf und was NICHT (Clara: sortiert, HR entscheidet).
--                        Damit die Grenze dokumentiert ist und nicht unbemerkt wächst.

begin;

create table if not exists public.ai_agents (
  key                text primary key,                  -- 'clara','max','anna','paul','maya'
  name               text not null,
  tagline            text,                              -- kurzer Steckbrief-Einzeiler
  avatar_url         text,                              -- Bild (später gepflegt)
  accent             text default '#0F5661',
  domain             text,                              -- Bereich in einem Wort ("Bewerber","Aufgaben",…)
  capabilities       text[] not null default '{}',      -- "Was ich kann"
  where_keys         text[] not null default '{}',      -- view-keys, wo der Agent arbeitet/auftaucht
  outward_facing     boolean not null default false,    -- tritt der Agent nach außen auf (Mails etc.)?
  disclosure         text,                              -- Außen-Kennzeichnung (Pflicht wenn outward_facing)
  decision_authority jsonb not null default '{"darf":[],"darf_nicht":[]}'::jsonb,
  visibility         text not null default 'all' check (visibility in ('all','management')),
  active             boolean not null default true,
  seq                int not null default 0,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
alter table public.ai_agents enable row level security;
-- Lesen: 'all'-Agenten für jeden HR-Portal-Nutzer, 'management'-Agenten (Maya) nur fürs Management.
drop policy if exists ai_agents_sel on public.ai_agents;
create policy ai_agents_sel on public.ai_agents for select to authenticated
  using ( visibility = 'all' or public.is_management() );
-- Schreiben: nur Management.
drop policy if exists ai_agents_write on public.ai_agents;
create policy ai_agents_write on public.ai_agents for all to authenticated
  using (public.is_management()) with check (public.is_management());
grant select, insert, update, delete on public.ai_agents to authenticated;

-- ── Die fünf ──────────────────────────────────────────────────────────────────
insert into public.ai_agents(key,name,tagline,domain,accent,capabilities,where_keys,outward_facing,disclosure,decision_authority,visibility,seq) values
 ('clara','Clara','Kümmert sich um alles rund um Bewerber.','Bewerber','#6366f1',
   array['Bewerbungen vorqualifizieren und vorsortieren','Mails an Bewerber verschicken','Termine vorschlagen','Datenerhebung anstoßen'],
   array['kanban','cvs','funnel','bewerberlinks'], true, 'Clara ist eine digitale Assistentin bei 25HRS, keine Person.',
   '{"darf":["Bewerbungen vorsortieren und markieren","standardisierte Mails/Links verschicken"],"darf_nicht":["über Annahme oder Absage entscheiden — das macht HR"]}'::jsonb,
   'all', 1),
 ('max','Max','Erinnert und hält Aufgaben im Blick.','Aufgaben','#0d9488',
   array['Tagesaufgaben zusammenstellen und erinnern','über Slack/Cliq benachrichtigen','Upload-Ampel überwachen'],
   array['daily_tasks','uploads','uploadplan'], true, 'Max ist ein digitaler Assistent bei 25HRS, keine Person.',
   '{"darf":["erinnern und benachrichtigen","Fälligkeiten anzeigen"],"darf_nicht":["Aufgaben eigenständig als erledigt markieren"]}'::jsonb,
   'all', 2),
 ('anna','Anna','Beantwortet Fragen zum System und zu den Daten.','Auskunft','#0F5661',
   array['Fragen zum System beantworten (Wissensbereich)','Datenfragen in Auswertungen übersetzen (Datenabfrage)'],
   array['wissen_system','nlquery'], false, null,
   '{"darf":["auskunftgeben und den Weg zeigen","Lese-Abfragen übersetzen"],"darf_nicht":["Daten verändern"]}'::jsonb,
   'all', 3),
 ('paul','Paul','Fasst zusammen und wertet aus.','Analyse','#b45309',
   array['Berichte und Auswertungen aufbereiten','Besprechungen zusammenfassen','Texte sprachlich säubern'],
   array['praesentation','auswertung','meetingnotes'], false, null,
   '{"darf":["zusammenfassen und aufbereiten","Textvorschläge machen"],"darf_nicht":["Inhalte eigenmächtig ändern oder veröffentlichen"]}'::jsonb,
   'all', 4),
 ('maya','Maya','Behält die Nutzung im Blick. Zeigt, was ist, ohne Wertung.','Systemüberwachung','#334155',
   array['Aktivitäten und Anmeldungen überblicken','tägliche Nutzungs-Zusammenfassung','wer arbeitet womit'],
   array['useractivity'], false, null,
   '{"darf":["Nutzung sachlich darstellen"],"darf_nicht":["Personen bewerten oder einordnen — das macht das Management"]}'::jsonb,
   'management', 5)
on conflict (key) do nothing;

commit;
