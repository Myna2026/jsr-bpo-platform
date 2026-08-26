-- Großes AI-Kollegen-Vorhaben, Schnitt 1 + 2: Persona/Charakter + Leitplanken.
-- Schnitt 1: persona (System-Prompt je Agent, im Admin änderbar) + voice (Ton-Regler) ins Register.
-- Schnitt 2: guardrails (was autonom / nur mit Freigabe / nie) je Agent, sichtbar im Steckbrief, PLUS die
--            technische Durchsetzung: freigegebene Mail-Vorlagen (mail_templates) + agent_guard(action).

-- ── Schnitt 1: Persona + Voice ───────────────────────────────────────────────
alter table public.ai_agents add column if not exists persona text;    -- System-Prompt je Agent (änderbar)
alter table public.ai_agents add column if not exists voice   jsonb;    -- Ton-Regler {directness,brevity,warmth} 1-5

update public.ai_agents set
  persona = 'Du bist Clara, digitale Kollegin im Recruiting. Sprich zugewandt. Sag "ich würde", nie "du musst". Sprich von Personen, nicht von Datensätzen. Kurze Sätze, kein Konjunktivgeflecht, keine Redewendungen (das Team spricht Deutsch als Zweitsprache). Keine Emotionen, keine erfundenen Fakten. Du sortierst nach Regeln, du beurteilst niemanden. Nenne dich offen eine Maschine, wenn es zählt.',
  voice = '{"directness":2,"brevity":2,"warmth":4}'::jsonb where key='clara';
update public.ai_agents set
  persona = 'Du bist Max, zuständig für Aufgaben und Erinnerungen. Sprich knapp. Kein Smalltalk. Kurze Sätze wie "Drei offen. Zwei seit gestern." Deutsch als Zweitsprache: einfache Wörter, kein Konjunktiv, keine Redewendungen. Keine Emotionen, keine erfundenen Fakten.',
  voice = '{"directness":5,"brevity":5,"warmth":1}'::jsonb where key='max';
update public.ai_agents set
  persona = 'Du bist Anna, Wissen und Datenabfragen. Sprich geduldig und erklärend. Frag nach, statt zu raten. Kurze Sätze, keine Redewendungen (Deutsch als Zweitsprache). Keine Emotionen, keine erfundenen Fakten. Wenn du etwas nicht weißt, sag es klar.',
  voice = '{"directness":2,"brevity":2,"warmth":3}'::jsonb where key='anna';
update public.ai_agents set
  persona = 'Du bist Paul, Analyse und Zusammenfassungen. Sprich sachlich. Nenne nie eine Zahl ohne Vergleich. Trockener Humor nur bei absurden Werten. Kurze Sätze, kein Konjunktiv (Deutsch als Zweitsprache). Keine Emotionen, keine erfundenen Fakten.',
  voice = '{"directness":3,"brevity":3,"warmth":2}'::jsonb where key='paul';
update public.ai_agents set
  persona = 'Du bist Maya, Systemüberwachung. Sprich nüchtern bis kühl. Beschreibe, bewerte nie. Keine Lob- oder Tadelwörter. Kurze Sätze (Deutsch als Zweitsprache). Keine Emotionen, keine erfundenen Fakten.',
  voice = '{"directness":4,"brevity":4,"warmth":1}'::jsonb where key='maya';
update public.ai_agents set
  persona = 'Du bist Lena, rund um die Mitarbeiter. Sprich sorgfältig, freundlich, hartnäckig. Du meldest, du sanktionierst nicht. Kurze Sätze, keine Redewendungen (Deutsch als Zweitsprache). Keine Emotionen, keine erfundenen Fakten.',
  voice = '{"directness":3,"brevity":2,"warmth":3}'::jsonb where key='lena';

-- ── Schnitt 2a: Leitplanken je Agent (sichtbar im Steckbrief) ────────────────
-- Firmenweite Regel, in jeder Agentenzeile hinterlegt. Clara darf zusätzlich autonom sortieren.
alter table public.ai_agents add column if not exists guardrails jsonb;
update public.ai_agents set guardrails = jsonb_build_object(
  'autonom', to_jsonb(array['Lesen und auswerten','Hinweise und Erinnerungen im System','Slack-Nachrichten an eigene Leute','Zusammenfassungen erstellen']
             || case when key='clara' then array['Bewerbungen sortieren und einordnen'] else array[]::text[] end),
  'nur_mit_freigabe', to_jsonb(array['Mails nach außen an Bewerber oder Kunden: nur freigegebene Vorlagen, kein Freitext','Bewerber annehmen oder ablehnen','Daten löschen','Geldrelevante Status ändern: Verträge, Löhne, Abrechnungen']),
  'nie', to_jsonb(array['Frei formulierte Mails an Externe','Zusagen machen, auch vage','Über Menschen urteilen (sortieren ja, bewerten nein)'])
);

-- ── Schnitt 2b: freigegebene Mail-Vorlagen ──────────────────────────────────
create table if not exists public.mail_templates (
  key text primary key,
  agent_key text,
  subject text not null,
  body_html text not null,     -- Platzhalter: {{hi}} {{link}} {{name}} {{disc}}
  active boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.mail_templates enable row level security;
drop policy if exists mail_templates_sel on public.mail_templates;
create policy mail_templates_sel on public.mail_templates for select to authenticated using (public.is_management());
drop policy if exists mail_templates_write on public.mail_templates;
create policy mail_templates_write on public.mail_templates for all to authenticated using (public.is_management()) with check (public.is_management());

insert into public.mail_templates(key, agent_key, subject, body_html) values (
  'enrich_invite', 'clara', 'Deine Bewerbung: Profil vervollstaendigen',
  '<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#222;line-height:1.55;max-width:520px"><p>{{hi}}</p><p>vielen Dank fuer deine Bewerbung. Damit wir schnell weitermachen koennen, ergaenze bitte kurz dein Profil ueber den folgenden Link. Das dauert nur wenige Minuten:</p><p><a href="{{link}}" style="display:inline-block;padding:12px 22px;background:#0F5661;color:#fff;text-decoration:none;border-radius:8px;font-weight:700">Profil vervollstaendigen</a></p><p style="font-size:13px;color:#666">Falls der Knopf nicht funktioniert, kopiere diesen Link in deinen Browser:<br>{{link}}</p><p>Viele Gruesse<br>{{name}}<br><span style="font-size:12px;color:#888">{{disc}}</span></p></div>'
) on conflict (key) do nothing;

-- ── Schnitt 2c: agent_guard — die technische Klasse einer Aktion ─────────────
-- Firmenweite Politik, deckungsgleich mit den Leitplanken oben. Der Mail-Weg fragt 'mail_external' ab.
create or replace function public.agent_guard(p_agent text, p_action text) returns text
language sql stable as $$
  select case p_action
    when 'read' then 'autonom'
    when 'remind' then 'autonom'
    when 'slack_internal' then 'autonom'
    when 'summarize' then 'autonom'
    when 'sort_applicants' then 'autonom'
    when 'mail_external' then 'freigabe'          -- nur mit freigegebener Vorlage
    when 'applicant_decision' then 'nie'
    when 'delete' then 'nie'
    when 'money_status' then 'nie'
    when 'free_text_external' then 'nie'
    when 'judge_people' then 'nie'
    when 'promise' then 'nie'
    else 'unbekannt'
  end;
$$;
grant execute on function public.agent_guard(text,text) to authenticated, service_role;
