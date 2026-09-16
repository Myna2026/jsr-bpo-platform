-- =============================================================================
-- Condor Holidays · interner Bewertungsbogen (Ardita bewertet)                 2026-09-17
-- Quelle: Checkliste_Qualitaetspruefung_Callcenter.docx (Reiseveranstalter, Callcenter Qualitätskontrolle).
-- 8 Kategorien, 38 Kriterien, je 3 Punkte, tristate (ja=3 / teilweise=1,5 / nein=0), n.a. zählt wie ja.
--   Technik 12 · Gesprächsbeginn 21 · Freundlichkeit 15 · Bedarfsermittlung 12 · Fachkompetenz 18
--   · Lösungsorientierung 15 · Gesprächsabschluss 15 · Dokumentation 6  = 114 Punkte.
-- Kritische Fehler (das Wichtigste am Bogen): 7 Ja/Nein-Kriterien, compliance-kritisch, Gewicht 0 (keine Punkte
--   im Score, aber ein angekreuzter Fehler setzt den gesamten Call offiziell auf 0 (raw_points bleibt).
-- Ampel in Punkten: grün ab 103 (90 %), gelb ab 86 (75 %), sonst rot.
-- Skill NULL = gilt für alle Skills des Projekts (Condor-MA laufen unter 'overall').
-- Doppelung „Kunde willkommen geheißen" bewusst belassen (7 × 3 = 21), Ardita passt im Editor an.
-- rater_kind = intern. Idempotent: ersetzt den internen Condor-Bogen (skill NULL) + Config.
-- =============================================================================
do $$
declare pid text;
begin
  select id into pid from public.projects where id = 'proj_cd_c9d0e1f2';
  if pid is null then select id into pid from public.projects where name ilike '%condor%' limit 1; end if;
  if pid is null then raise exception 'Condor-Projekt nicht gefunden.'; end if;

  if exists (select 1 from public.call_samples where project_id = pid and rater_kind = 'intern') then
    raise exception 'Es gibt bereits interne Condor-Stichproben, Bogen nicht blind ersetzen.';
  end if;

  delete from public.call_criteria where project_id = pid and skill is null and rater_kind = 'intern';

  insert into public.call_criteria
    (project_id, skill, rater_kind, category, order_index, prompt, type, max_points, weight, allow_na, compliance_critical, hint, active)
  values
  -- 1 Technik (12)
  (pid,null,'intern','1 · Technik',110,'Sprachqualität klar und deutlich','tristate',3,1,true,false,null,true),
  (pid,null,'intern','1 · Technik',120,'Keine Störgeräusche','tristate',3,1,true,false,null,true),
  (pid,null,'intern','1 · Technik',130,'Kunde konnte den Mitarbeiter jederzeit verstehen','tristate',3,1,true,false,null,true),
  (pid,null,'intern','1 · Technik',140,'Mitarbeiter spricht in angemessener Lautstärke','tristate',3,1,true,false,null,true),
  -- 2 Gesprächsbeginn (21)
  (pid,null,'intern','2 · Gesprächsbeginn',210,'Freundliche, professionelle Begrüßung','tristate',3,1,true,false,null,true),
  (pid,null,'intern','2 · Gesprächsbeginn',220,'Marke genannt','tristate',3,1,true,false,null,true),
  (pid,null,'intern','2 · Gesprächsbeginn',230,'Eigener Name genannt','tristate',3,1,true,false,null,true),
  (pid,null,'intern','2 · Gesprächsbeginn',240,'Datenschutz-Abfrage','tristate',3,1,true,false,null,true),
  (pid,null,'intern','2 · Gesprächsbeginn',250,'Freundlicher erster Eindruck, Kunde willkommen geheißen','tristate',3,1,true,false,null,true),
  (pid,null,'intern','2 · Gesprächsbeginn',260,'Kunde willkommen geheißen','tristate',3,1,true,false,null,true),
  (pid,null,'intern','2 · Gesprächsbeginn',270,'Kunde nicht unterbrochen','tristate',3,1,true,false,null,true),
  -- 3 Freundlichkeit und Auftreten (15)
  (pid,null,'intern','3 · Freundlichkeit und Auftreten',310,'Freundlicher, zugewandter Tonfall','tristate',3,1,true,false,null,true),
  (pid,null,'intern','3 · Freundlichkeit und Auftreten',320,'Höfliche Ausdrucksweise','tristate',3,1,true,false,null,true),
  (pid,null,'intern','3 · Freundlichkeit und Auftreten',330,'Geduldig geblieben','tristate',3,1,true,false,null,true),
  (pid,null,'intern','3 · Freundlichkeit und Auftreten',340,'Wertschätzender Umgang','tristate',3,1,true,false,null,true),
  (pid,null,'intern','3 · Freundlichkeit und Auftreten',350,'Professionelles Auftreten','tristate',3,1,true,false,null,true),
  -- 4 Bedarfsermittlung (12)
  (pid,null,'intern','4 · Bedarfsermittlung',410,'Kunde ausreden lassen','tristate',3,1,true,false,null,true),
  (pid,null,'intern','4 · Bedarfsermittlung',420,'Aktiv zugehört (Rückbestätigung, Paraphrasieren)','tristate',3,1,true,false,null,true),
  (pid,null,'intern','4 · Bedarfsermittlung',430,'Gezielte Rückfragen gestellt','tristate',3,1,true,false,null,true),
  (pid,null,'intern','4 · Bedarfsermittlung',440,'Anliegen vollständig verstanden','tristate',3,1,true,false,null,true),
  -- 5 Fachliche Kompetenz (18)
  (pid,null,'intern','5 · Fachliche Kompetenz',510,'Richtige, vollständige Informationen gegeben','tristate',3,1,true,false,null,true),
  (pid,null,'intern','5 · Fachliche Kompetenz',520,'Sichere Produktkenntnisse','tristate',3,1,true,false,null,true),
  (pid,null,'intern','5 · Fachliche Kompetenz',530,'Richtige Beratung zur Reise','tristate',3,1,true,false,null,true),
  (pid,null,'intern','5 · Fachliche Kompetenz',540,'Buchung korrekt bearbeitet','tristate',3,1,true,false,null,true),
  (pid,null,'intern','5 · Fachliche Kompetenz',550,'Datenschutz eingehalten','tristate',3,1,true,false,null,true),
  (pid,null,'intern','5 · Fachliche Kompetenz',560,'Keine falschen Versprechungen oder Zusagen','tristate',3,1,true,false,null,true),
  -- 6 Lösungsorientierung (15)
  (pid,null,'intern','6 · Lösungsorientierung',610,'Passende Lösung angeboten','tristate',3,1,true,false,null,true),
  (pid,null,'intern','6 · Lösungsorientierung',620,'Alternativen aufgezeigt','tristate',3,1,true,false,null,true),
  (pid,null,'intern','6 · Lösungsorientierung',630,'Nächste Schritte erklärt','tristate',3,1,true,false,null,true),
  (pid,null,'intern','6 · Lösungsorientierung',640,'Verantwortung übernommen','tristate',3,1,true,false,null,true),
  (pid,null,'intern','6 · Lösungsorientierung',650,'Problem gelöst oder korrekt weitergeleitet','tristate',3,1,true,false,null,true),
  -- 7 Gesprächsabschluss (15)
  (pid,null,'intern','7 · Gesprächsabschluss',710,'Anliegen zusammengefasst und geklärt','tristate',3,1,true,false,null,true),
  (pid,null,'intern','7 · Gesprächsabschluss',720,'Fragen angeboten','tristate',3,1,true,false,null,true),
  (pid,null,'intern','7 · Gesprächsabschluss',730,'Freundliche Verabschiedung','tristate',3,1,true,false,null,true),
  (pid,null,'intern','7 · Gesprächsabschluss',740,'Für den Anruf bedankt','tristate',3,1,true,false,null,true),
  (pid,null,'intern','7 · Gesprächsabschluss',750,'Positiver Gesamteindruck','tristate',3,1,true,false,null,true),
  -- 8 Dokumentation (6)
  (pid,null,'intern','8 · Dokumentation',810,'Gespräch zusammengefasst und korrekt dokumentiert (Midoco)','tristate',3,1,true,false,null,true),
  (pid,null,'intern','8 · Dokumentation',820,'Alle relevanten Daten erfasst','tristate',3,1,true,false,null,true),
  -- Kritische Fehler: Ja/Nein, compliance-kritisch, Gewicht 0 (keine Punkte, nur der K.o.-Effekt zählt). prompt positiv formuliert
  -- (ja = kein Fehler), hint = der Fehler, wie er im Bogen heißt (so erscheint er in der Ankreuzliste).
  (pid,null,'intern','Kritische Fehler',910,'Kein unhöfliches Verhalten','yesno',1,0,false,true,'Unhöfliches Verhalten',true),
  (pid,null,'intern','Kritische Fehler',920,'Keine falsche Beratung','yesno',1,0,false,true,'Falsche Beratung',true),
  (pid,null,'intern','Kritische Fehler',930,'Datenschutz nicht verletzt','yesno',1,0,false,true,'Datenschutz verletzt',true),
  (pid,null,'intern','Kritische Fehler',940,'Kunde nicht beleidigt oder unterbrochen','yesno',1,0,false,true,'Kunde beleidigt oder unterbrochen',true),
  (pid,null,'intern','Kritische Fehler',950,'Keine unprofessionelle Ausdrucksweise','yesno',1,0,false,true,'Unprofessionelle Ausdrucksweise',true),
  (pid,null,'intern','Kritische Fehler',960,'Keine falsche Buchung','yesno',1,0,false,true,'Falsche Buchung',true),
  (pid,null,'intern','Kritische Fehler',970,'Gespräch nicht ohne Lösung beendet','yesno',1,0,false,true,'Gespräch ohne Lösung beendet',true);

  if exists (select 1 from public.call_score_config where project_id = pid and skill is null and rater_kind = 'intern') then
    update public.call_score_config set threshold_unit='points', green_min=103, yellow_min=86, updated_at=now()
     where project_id = pid and skill is null and rater_kind = 'intern';
  else
    insert into public.call_score_config (project_id, skill, rater_kind, threshold_unit, green_min, yellow_min)
    values (pid, null, 'intern', 'points', 103, 86);
  end if;
end $$;
