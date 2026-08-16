-- =============================================================================
-- HolidayCheck · Support · Bewertungsbogen                                     2026-08-16
-- 8 Kriterien in 4 Kategorien, je max 1 Punkt, ungewichtet, tristate
-- (ja=1/teilweise=0,5/nein=0), n.a. erlaubt (zaehlt wie ja) AUSSER beim
-- compliance-kritischen Datenabgleich.
-- Ampel in PUNKTEN: gruen ab 7, gelb ab 4, sonst rot (0-3 rot / 4-6 gelb / 7-8 gruen).
--
-- Datenabgleich (Nr 2) ist COMPLIANCE-KRITISCH: nur ja/nein (kein teilweise),
-- kein n.a.; bei "nein" faellt der GESAMTE Call auf 0 Punkte.
--
-- Voraussetzung: call_samples.sql + call_tristate.sql + call_compliance_critical.sql eingespielt.
-- Zwei unabhaengige Bloecke, IN DIESER REIHENFOLGE ausfuehren:
--   Block 1 loescht den alten Support-Bogen und legt Einstieg + Kommunikation an (5 Kriterien).
--   Block 2 legt Fachkenntnisse + Abschluss an (3 Kriterien) + die Config.
-- Zum erneuten Einspielen beide Bloecke wieder nacheinander laufen lassen.
-- Rueckmeldungstexte (feedback_*) bleiben vorerst leer (vom User so gewuenscht).
-- =============================================================================

-- ── BLOCK 1: Einstieg (2) + Kommunikation (3) ────────────────────────────────
do $$
declare pid text;
begin
  select id into pid from public.projects where lower(name) = 'holidaycheck' limit 1;
  if pid is null then select id into pid from public.projects where name ilike '%holidaycheck%' limit 1; end if;
  if pid is null then raise exception 'HolidayCheck-Projekt nicht gefunden — bitte Projektnamen pruefen.'; end if;

  delete from public.call_criteria where project_id = pid and skill = 'support';

  insert into public.call_criteria
    (project_id, skill, category, order_index, prompt, type, max_points, weight, allow_na, compliance_critical, agent_hint, level_hints, active)
  values
  (pid,'support','Einstieg',10,'Begrüßung','tristate',1,1,true,false,
   'Wir heißen jeden Urlauber freundlich, motiviert und vollständig willkommen. Beispiel: Herzlich Willkommen bei HolidayCheck. Mein Name ist Vorname Nachname. Was kann ich für Sie tun?',
   null,true),

  (pid,'support','Einstieg',20,'Datenabgleich','tristate',1,1,false,true,
   'Für den Datenabgleich fragen wir zu Beginn eines jeden Gesprächs nach den Eckdaten: buID falls diese noch nicht vorliegt, vollständiger Name des Anrufers wenn er diesen noch nicht genannt hat, plus ein Reisedetail wie Reisedatum oder Hotel. Beispiel: Bitte nennen Sie mir zum Datenabgleich noch... (Compliance-kritisch: nur korrekt oder nicht korrekt, kein teilweise.)',
   null,true),

  (pid,'support','Kommunikation',30,'Hörbare Freundlichkeit, Tonlage, Sprechgeschwindigkeit','tristate',1,1,true,false,
   'Ist der Agent empathisch, kann der Anrufer ihm inhaltlich folgen, spricht der Agent in einer für den Anrufer angemessenen Geschwindigkeit und Lautstärke? Beispiel: Namensansprache mindestens einmal pro Call.',
   null,true),

  (pid,'support','Kommunikation',40,'Gesprächsstruktur','tristate',1,1,true,false,
   'Wir lassen den Anrufer aussprechen, übernehmen die strukturierte Führung des Gesprächs und haben kaum Gesprächspausen. Beispiel: Gespräch ist strukturiert, Kunde wird ausreden gelassen, Wartezeiten werden angekündigt und spätestens nach 3 Minuten aktiv erklärt. Ist die Nacharbeit angemessen?',
   null,true),

  (pid,'support','Kommunikation',50,'Anliegen des Kunden verstanden','tristate',1,1,true,false,
   'Versteht der Agent, was der Anrufer wissen möchte, worum es in dem Call geht? Beispiel: Der Agent stellt gegebenenfalls Rückfragen, um das Anliegen zu erfassen. Er fasst das Anliegen mit eigenen Worten zusammen.',
   null,true);

  raise notice 'Block 1: Einstieg + Kommunikation angelegt (5 Kriterien, Projekt %).', pid;
end $$;

-- ── BLOCK 2: Fachkenntnisse (1) + Abschluss (2) + Config ──────────────────────
do $$
declare pid text;
begin
  select id into pid from public.projects where lower(name) = 'holidaycheck' limit 1;
  if pid is null then select id into pid from public.projects where name ilike '%holidaycheck%' limit 1; end if;
  if pid is null then raise exception 'HolidayCheck-Projekt nicht gefunden — bitte Projektnamen pruefen.'; end if;

  insert into public.call_criteria
    (project_id, skill, category, order_index, prompt, type, max_points, weight, allow_na, compliance_critical, agent_hint, level_hints, active)
  values
  (pid,'support','Fachkenntnisse',60,'Lösung laut Call und Eintrag im Vorgang korrekt','tristate',1,1,true,false,
   'Hat der Agent die richtige Lösung auf den Weg gebracht? Beispiel: RBE wird über Iris erneut versendet. Eintrag im Vorgang vollständig.',
   null,true),

  (pid,'support','Abschluss',70,'Zusammenfassung und Anliegen gelöst','tristate',1,1,true,false,
   'Wurde das Anliegen des Kunden am Telefon gelöst? Hätte es gelöst werden können oder müssen? Was wird dem Kunden als weiteres Vorgehen präsentiert? Beispiel: Ich sende die Anfrage per Mail an den VA, sobald uns eine Rückmeldung vorliegt informieren wir Sie per E-Mail, das dauert in der Regel drei Werktage.',
   null,true),

  (pid,'support','Abschluss',80,'Verabschiedung','tristate',1,1,true,false,
   'Wir fragen den Anrufer nach sonstigen Anliegen, bedanken uns für den Anruf und verabschieden uns. Beispiel: Haben Sie noch weitere Fragen? Vielen Dank für Ihren Anruf, ich wünsche Ihnen einen schönen Tag, auf Wiederhören.',
   null,true);

  if exists (select 1 from public.call_score_config where project_id = pid and skill = 'support') then
    update public.call_score_config set
      threshold_unit='points', green_min=7, yellow_min=4,
      feedback_green=null, feedback_amber=null, feedback_red=null,
      updated_at=now()
    where project_id = pid and skill = 'support';
  else
    insert into public.call_score_config (project_id, skill, threshold_unit, green_min, yellow_min)
    values (pid,'support','points',7,4);
  end if;

  raise notice 'Block 2: Fachkenntnisse + Abschluss + Config angelegt (3 Kriterien, Ampel Punkte 7/4, Projekt %).', pid;
end $$;
