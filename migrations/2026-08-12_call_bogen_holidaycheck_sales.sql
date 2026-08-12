-- =============================================================================
-- HolidayCheck · Sales · Bogen "Sales Junior mit Buchung"                     2026-08-12
-- 15 Kriterien, je max 1 Punkt, ungewichtet, tristate (ja=1/teilweise=0,5/nein=0),
-- n.a. erlaubt (zählt wie ja). Ampel in PUNKTEN: grün ab 11, gelb ab 7, sonst rot.
--
-- Voraussetzung: 2026-08-12_call_samples.sql + 2026-08-12_call_tristate.sql eingespielt.
-- Idempotent: ersetzt den vorhandenen Sales-Bogen (noch keine Stichproben) + Config.
-- Projekt wird über den Namen aufgelöst; Skill-Key = 'sales' (kleingeschrieben, wie im Frontend).
-- Im Supabase SQL-Editor ausführen.
-- =============================================================================
do $$
declare pid text;
begin
  select id into pid from public.projects where lower(name) = 'holidaycheck' limit 1;
  if pid is null then select id into pid from public.projects where name ilike '%holidaycheck%' limit 1; end if;
  if pid is null then raise exception 'HolidayCheck-Projekt nicht gefunden — bitte Projektnamen prüfen.'; end if;

  -- vorhandenen Sales-Bogen ersetzen (idempotent bei erneutem Lauf)
  delete from public.call_criteria where project_id = pid and skill = 'sales';

  insert into public.call_criteria
    (project_id, skill, category, order_index, prompt, type, max_points, weight, allow_na, agent_hint, level_hints, active)
  values
  (pid,'sales',null,10,'Begrüßung','tristate',1,1,true,
   'Herzlich Willkommen bei HolidayCheck, ich bin Vorname Nachname, wie darf ich Ihnen helfen?',
   jsonb_build_object('yes','Warm, empathisch, freundlich und vollständig','partial','Neutral, nur Vor- oder Nachname genannt, Lächeln in der Stimme fehlt','no','Kalt oder genervt, nur Vor- oder Nachname genannt, keinen Namen genannt'),true),

  (pid,'sales',null,20,'Hörbare Freundlichkeit','tristate',1,1,true,
   'Lächle beim Sprechen, klinge warm, interessiert und positiv',
   jsonb_build_object('yes','Warm, empathisch','partial','Neutral','no','Kalt oder genervt'),true),

  (pid,'sales',null,30,'Variation in der Tonlage','tristate',1,1,true,
   'Vermeide monotonen Singsang, betone Wichtiges natürlich und passend zur Situation',
   jsonb_build_object('yes','Lebendig, betont','partial','Teils monoton','no','Gleichförmig, emotionslos'),true),

  (pid,'sales',null,40,'Sprechgeschwindigkeit und Pausen','tristate',1,1,true,
   'Sprich klar, weder zu schnell noch zu langsam, passe dich dem Tempo des Kunden an. Kündige Gesprächspausen an',
   jsonb_build_object('yes','Verständlich, angepasst, Gesprächspause angekündigt oder max 8 Sekunden','partial','Etwas zu schnell oder langsam, Pausen nicht angekündigt und länger als 8 Sekunden','no','Unangemessen, schwer verständlich und mehrere unangekündigte Gesprächspausen jeweils länger als 8 Sekunden'),true),

  (pid,'sales',null,50,'Gesprächsstruktur','tristate',1,1,true,
   'Ich übernehme das gerne für Sie, dazu brauche ich nur kurz folgende Angaben. Ich fasse noch mal kurz zusammen, damit Sie alles im Blick haben',
   jsonb_build_object('yes','Agent führt das Gespräch, geht auf den Urlauber ein, übernimmt die Führung und behält den roten Faden, nennt nächsten Schritte','partial','Berater gibt zwar Impulse, überlässt zwischendurch dem Kunden die Führung, was zu leichtem Abschweifen führt, Struktur wird nicht konsequent durchgehalten','no','Unterbricht den Urlauber oft, oder Anrufer führt durch das Gespräch, reagiert nur, statt pro aktiv nach zu fragen und hört nicht zu, Kunde muss Sachen wiederholen'),true),

  (pid,'sales',null,60,'Anliegen des Kunden verstanden','tristate',1,1,true,
   'Wir hören aktiv zu und lassen Kunden ausreden. Wir stellen bei Bedarf gezielte Rückfragen, um das Hauptanliegen eindeutig zu klären. Wir fassen insbesondere bei komplexeren Gesprächen das Anliegen in eigenen Worten zusammen',
   jsonb_build_object('yes','Agent hört aktiv zu, lässt den Kunden ausreden, stellt bei Bedarf gezielte Rückfragen und fasst das Anliegen gegebenenfalls in eigenen Worten zusammen. Das Hauptanliegen ist klar erkannt','partial','Agent erkennt im Kern zu und erfasst das Grundanliegen, aber Rückfragen bleiben oberflächlich oder eine Zusammenfassung erfolgt nicht. Feinheiten oder Nebenpunkte werden teilweise übersehen. Bei neuen Agenten halber Punkt, wenn das Hauptanliegen korrekt erkannt wurde','no','Agent hört nicht richtig zu, Kunde muss Inhalte wiederholen, Rückfragen fehlen oder das Hauptanliegen wird falsch verstanden. Gespräch entwickelt sich in eine falsche Richtung'),true),

  (pid,'sales',null,70,'Bedarf und Angebot korrekt ermittelt','tristate',1,1,true,
   'Wir fragen gezielt nach, ob der Kunde das Angebot gesehen hat, zum Beispiel über den Punkt oder die Angebots-ID. Liegt kein konkretes Angebot vor, stellen wir offene Fragen zu Ziel, Zeitraum, Personen, Alter, Budget und Präferenzen. Wir notieren die relevanten Informationen, grenzen die Auswahl bewusst ein und nennen maximal 1 bis 3 passende Optionen',
   jsonb_build_object('yes','Bedarf oder roter Punkt klar erfasst, Eckdaten vollständig dokumentiert, Auswahl bewusst eingegrenzt auf 1 bis 3 passende Optionen, aktiv nach Angebot gefragt, Kontaktdaten erfragt','partial','Bedarf teilweise erfasst, Fragen oberflächlich oder unvollständig, der Eingrenzung nicht konsequent, Nachfrage zum Angebot oder Kontaktdaten unvollständig','no','Bedarf nicht sauber aufgenommen, keine gezielten Fragen, Annahmen getroffen, unpassende oder zufällige Auswahl, keine Nachfrage zum Angebot, Kontaktdaten nicht erfragt'),true),

  (pid,'sales',null,80,'Angebotspräsentation','tristate',1,1,true,
   'Nachdem der Bedarf ermittelt wurde, präsentieren wir dem Kunden das Angebot vollständig und stellen, wo möglich, einen Mehrwert heraus. Wenn ein Wunsch nicht umsetzbar ist, wird bei ähnlichen Optionen der Vorteil der Alternative betont',
   jsonb_build_object('yes','Angebot vollständig, klar und bedarfsorientiert präsentiert. Alle relevanten Punkte genannt: Hotel, Lage, Zimmer, Verpflegung, Preis inklusive Währung, Besonderheiten. Bezug zu den Kundenwünschen deutlich, Vorteile aktiv hervorgehoben und positive Sprache verwendet','partial','Teilweise unvollständig oder oberflächlich. Angebot grundsätzlich passend, aber einzelne Informationen fehlen, zum Beispiel Währung, keine Zimmerart, Nutzen nicht betont. Präsentation sachlich, aber wenig verkaufsfördernd','no','Unzureichend oder fehlerhaft. Nur Preis oder Teilinformationen genannt. Keine Erläuterung, kein Bezug zu Kundenwünschen, keine Nutzenargumentation oder negative Darstellung von Alternativen'),true),

  (pid,'sales',null,90,'Abschlussfrage','tristate',1,1,true,
   'Kunde wird aktiv gefragt, ob die Reise gebucht werden soll. Wenn nein, wird eine Reservierung geprüft. Der Kunde sollte aber zumindest ein Angebot versendet bekommen. Soll ich das direkt für Sie festhalten?',
   jsonb_build_object('yes','Abschlussfrage wird aktiv gestellt, zum Beispiel Möchten Sie die Buchung direkt vornehmen? oder Soll ich Ihnen das Angebot zusenden? Oder: Die Abschlussfrage wäre im Gesprächsverlauf nicht sinnvoll oder nicht möglich, zum Beispiel rein informativer Anruf ohne Angebots- oder Verkaufsbezug, dann trotzdem volle Punktzahl','partial','Abschlussfrage wird nur indirekt oder unvollständig gestellt, zum Beispiel Dann hören wir voneinander ohne konkrete Aktion anzubieten, Urlauber führt Agenten durch nachfragen dazu','no','Es wird nicht nach einer Buchung, Reservierung oder Angebotsversand gefragt oder angeboten'),true),

  (pid,'sales',null,100,'Vertragsinfos und Rechtliches','tristate',1,1,true,
   'Nutzt der Agent die vorvertraglichen Informationen als Strukturhilfe, um die Buchungsdaten vollständig und korrekt zusammenzufassen und sich die Bestätigung des Kunden einzuholen? Vor Abschluss nennt er die geltenden AGB, es gelten die AGB des Veranstalters und von HolidayCheck',
   jsonb_build_object('yes','VVI vollständig vorgelesen, keine Auslassungen, Verständnis aktiv geprüft, Passt das so für Sie?, wichtige Punkte wie Storno, Zahlungsmodalitäten, Bedingungen klar betont, AGB des Veranstalters und von HolidayCheck nachweislich genannt, gegebenenfalls VVI im Anschluss versendet und Versand bestätigt','partial','Einzelne Punkte ausgelassen oder nur oberflächlich erwähnt, Verständnisprüfung fehlt oder ist unzureichend, AGB nur teilweise oder undeutlich genannt','no','VVI nicht oder stark verkürzt vorgelesen, AGB nicht genannt oder fehlerhaft wiedergegeben'),true),

  (pid,'sales',null,110,'Zusatzverkauf','tristate',1,1,true,
   'Auch bei Optionen oder bei Buchung fragen wir aktiv nach, ob eine Reiserücktritts- oder Reiseversicherung benötigt wird. Idealerweise machen wir kurz auf den Nutzenaufmerksam, zum Beispiel Schutz bei Krankheit oder Storno. Ablehnung oder Angebot unerwünscht wird als Zusatzleistung angelegt, außer OSL-Link-Buchungen',
   jsonb_build_object('yes','Aktiv nach Reiserücktritts- oder Reiseversicherung gefragt, Pflicht erfüllt, Kurz den Nutzen genannt, zum Beispiel Schutz bei Krankheit oder Storno, bei Ablehnung dokumentiert. Wenn kein Verkauf stattfand ebenfalls 1 Punkt','partial','Versicherung wurde angesprochen, jedoch keine Dokumentation im Vorgang, Ausnahme OSL, Versicherungsfrage ist optimierbar','no','Versicherung wird gar nicht aktiv angeboten, weder Nutzen noch Dokumentation bei Ablehnung'),true),

  (pid,'sales',null,120,'Daten','tristate',1,1,true,
   'Wir erfassen die Namen aller Reisenden genau so, wie sie im Ausweis stehen, und lassen uns die Namen buchstabieren, inklusive Doppelnamen und Sonderzeichen. Wir erfassen auch die Geburtsdaten aller Mitreisenden und bestätigen die Schreibweise aktiv zurück',
   jsonb_build_object('yes','Namen laut Ausweis oder Pass aktiv erfragt und buchstabieren lassen, inklusive Doppelnamen, Sonderzeichen, alle Mitreisenden inklusive Geburtsdaten erfasst, Nationalität erfragt','partial','Nicht buchstabieren lassen oder Namen unvollständig erfasst oder Geburtsdaten nicht bei allen Mitreisenden aufgenommen','no','Namen nicht korrekt oder teilweise erfasst, keine Buchstabierung oder Rückbestätigung, falsche Schreibweise im Vorgang'),true),

  (pid,'sales',null,130,'Datenschutz','tristate',1,1,true,
   'Keine Daten aus Altvorgängen nennen, nur abgleichen. Daten nur mit Reisenden klären. Keine personenbezogenen Details an Dritte herausgeben. Ich habe hier eine Buchung vom September 2024 vor mir, darf ich die Daten daraus mit Ihnen abgleichen?',
   jsonb_build_object('yes','Keine Daten aus alter ID genannt, nur abgleichen, Daten nur mit dem Reisenden besprochen, keine personenbezogenen Details an Dritte herausgegeben','partial','Grundsätzlich Datenschutz beachtet, jedoch einzelne Details aus alter ID unnötig genannt, kleine Formulierungsungenauigkeiten','no','Personenbezogene Daten an falsche Person weitergegeben, Daten aus Altvorgängen ohne Anlass oder an Unbefugte genannt, Daten selbst raus gezogen mit Telefonnummer und dabei keinen Abgleich gemacht'),true),

  (pid,'sales',null,140,'Lösung','tristate',1,1,true,
   'Wir bieten eine passende Lösung an oder erklären, wie es weitergeht. Wir gehen auch auf zusätzliche Fragen ein, die im Gespräch entstehen. Wir achten darauf, dass unsere Lösung fachlich korrekt ist und zum geschilderten Anliegen passt. Der Kunde weiß am Ende des Gesprächs, was der nächste Schritt ist',
   jsonb_build_object('yes','Hauptanliegen wird gelöst oder ein klarer nächster Schritt aufgezeigt. Zusatzfragen werden berücksichtigt. Die vorgeschlagene Lösung passt zum Anliegen des Kunden und der Kunde weiß am Ende des Gesprächs, was die nächsten Schritte sind','partial','Hauptanliegen wird grundsätzlich bearbeitet und die Lösung geht in die richtige Richtung, jedoch bleiben einzelne Fragen offen oder die Lösung ist nicht vollständig oder konkret erklärt. Die nächsten Schritte sind nur teilweise klar. Besonders bei neuen Agenten halber Punkt, wenn das Grundanliegen korrekt bearbeitet wurde','no','Keine passende Lösung oder falsche fachliche Aussage. Wichtige Fragen bleiben unbeantwortet oder die Lösung passt nicht zum Anliegen. Der Kunde bleibt ohne klare Orientierung, wie es weitergeht'),true),

  (pid,'sales',null,150,'Verabschiedung','tristate',1,1,true,
   'Wir fragen den Anrufer nach sonstigen Anliegen, bedanken uns für den Anruf und verabschieden uns. Haben Sie noch weitere Fragen? Vielen Dank für Ihren Anruf, ich wünsche Ihnen einen schönen Tag, auf Wiederhören. Yo, Tschüss ist keine Verabschiedung',
   jsonb_build_object('yes','Am Ende des Gesprächs wird aktiv nach weiteren Anliegen gefragt, Gibt es sonst noch etwas, wobei ich helfen kann?, Dank für den Anruf und freundlicher Abschiedsgruß','partial','Eine der Punkte fehlt','no','Gespräch endet ohne Nachfrage nach weiteren Anliegen, kein Dank und keine klare Verabschiedung'),true);

  -- Bogen-Einstellungen: Punkte, grün ab 11, gelb ab 7 + Rückmeldungstexte
  if exists (select 1 from public.call_score_config where project_id = pid and skill = 'sales') then
    update public.call_score_config set
      threshold_unit='points', green_min=11, yellow_min=7,
      feedback_green='Sehr gutes Fundament, starke Basis, viele Kriterien schon sicher erfüllt. Weiter so!',
      feedback_amber='Gut in Entwicklung: Eine solide Basis ist vorhanden. Einzelne Punkte brauchen noch Übung - normal für Beginner. Du bist auf einem guten Weg!',
      feedback_red='Lernbereich - Fokus für Wachstum. Hier starten wir gemeinsam rein. Fokus auf Lernschritte und Training - absolut normal bei neuen Tools und Fertigkeiten.',
      updated_at=now()
    where project_id = pid and skill = 'sales';
  else
    insert into public.call_score_config (project_id, skill, threshold_unit, green_min, yellow_min, feedback_green, feedback_amber, feedback_red)
    values (pid,'sales','points',11,7,
      'Sehr gutes Fundament, starke Basis, viele Kriterien schon sicher erfüllt. Weiter so!',
      'Gut in Entwicklung: Eine solide Basis ist vorhanden. Einzelne Punkte brauchen noch Übung - normal für Beginner. Du bist auf einem guten Weg!',
      'Lernbereich - Fokus für Wachstum. Hier starten wir gemeinsam rein. Fokus auf Lernschritte und Training - absolut normal bei neuen Tools und Fertigkeiten.');
  end if;

  raise notice 'HolidayCheck Sales Bogen angelegt: 15 Kriterien, Ampel Punkte 11/7 (Projekt %).', pid;
end $$;
