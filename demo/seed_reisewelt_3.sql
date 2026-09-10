-- Reisewelt-Demo Teil 3: Condor-Features als Reisewelt-Seed (Myna-Projekt).
-- Arbeitsplan (improvement_items) + Kunden-Bogen extern (call_criteria/config) + Beispiel-Bewertungen
-- (call_samples) + Kunde↔Team-Chat (client_team_messages) + Reisewelt-Kundenkonto (client_accounts).
-- Idempotent: räumt eigene Demo-Zeilen vorher weg. NUR aufs Myna-Projekt (ggznzbfauuqljoefwwop) einspielen.

-- ── Aufräumen (nur Reisewelt-Projekt) ───────────────────────────────────────
delete from public.improvement_comments where project_id='proj_rw_demo';
delete from public.improvement_items    where project_id='proj_rw_demo';
delete from public.client_team_messages  where project_id='proj_rw_demo';
delete from public.call_scores where sample_id in (select id from public.call_samples where project_id='proj_rw_demo' and rater_kind='extern');
delete from public.call_samples where project_id='proj_rw_demo' and rater_kind='extern';
delete from public.call_criteria where project_id='proj_rw_demo' and rater_kind='extern';
delete from public.call_score_config where project_id='proj_rw_demo' and rater_kind='extern';

-- ── Arbeitsplan: 6 Hauptpunkte + 2 Unterpunkte, gemischte Herkunft/Zustände ──
insert into public.improvement_items (id, project_id, parent_id, title, measures, priority, status, progress, origin, sort_order, start_date, due_date, created_by_name) values
 ('b1000000-0000-4000-8000-000000000001','proj_rw_demo',null,'Wartezeiten in der Hauptsaison senken',null,'sehr_wichtig','in_arbeit',50,'client',1,date '2026-09-01',date '2026-10-15','Reisewelt'),
 ('b1000000-0000-4000-8000-000000000002','proj_rw_demo',null,'Beratungsqualität bei Komplettpaketen heben',null,'wichtig','offen',0,'client',2,null,null,'Reisewelt'),
 ('b1000000-0000-4000-8000-000000000003','proj_rw_demo',null,'Umbuchungsprozess vereinfachen','Kurzanleitung erstellt, Schulung für die Agenten geplant.','wichtig','in_arbeit',50,'intern',3,date '2026-09-05',date '2026-09-30','Teamleitung'),
 ('b1000000-0000-4000-8000-000000000004','proj_rw_demo',null,'Reklamationsquote Ägypten-Saison senken',null,'sehr_wichtig','offen',0,'client',4,null,date '2026-09-05','Reisewelt'),
 ('b1000000-0000-4000-8000-000000000005','proj_rw_demo',null,'Cross-Selling Reiseversicherung standardisieren','Gesprächsleitfaden mit Versicherungs-Baustein ausgerollt.','notwendig','erledigt',100,'intern',5,date '2026-08-15',date '2026-09-01','Teamleitung'),
 ('b1000000-0000-4000-8000-000000000006','proj_rw_demo',null,'Erreichbarkeit am Wochenende verbessern',null,'wichtig','in_arbeit',50,'client',6,date '2026-09-08',date '2026-10-31','Reisewelt');
-- Unterpunkte zu „Wartezeiten"
insert into public.improvement_items (id, project_id, parent_id, title, measures, priority, status, progress, origin, sort_order, start_date, due_date, created_by_name) values
 ('b1000000-0000-4000-8000-0000000000a1','proj_rw_demo','b1000000-0000-4000-8000-000000000001','Zusätzliche Agenten für Sept/Okt einplanen','2 Agenten aus dem Pool aufgestockt.','wichtig','erledigt',100,'intern',1,date '2026-09-01',date '2026-09-10','Teamleitung'),
 ('b1000000-0000-4000-8000-0000000000a2','proj_rw_demo','b1000000-0000-4000-8000-000000000001','Callback-Option in der Hauptsaison anbieten','Rückruf-Slot im Tool aktiviert, Pilot läuft.','wichtig','in_arbeit',50,'intern',2,date '2026-09-08',date '2026-10-01','Teamleitung');

-- Ein Kommentar je Seite (zeigt den gemeinsamen Charakter)
insert into public.improvement_comments (item_id, project_id, side, author_name, body) values
 ('b1000000-0000-4000-8000-000000000001','proj_rw_demo','client','Reisewelt','Gerade freitags nachmittags sind die Wartezeiten zu lang.'),
 ('b1000000-0000-4000-8000-000000000001','proj_rw_demo','team','Teamleitung','Verstanden, wir schauen gezielt auf das Freitag-Nachmittag-Fenster.');

-- ── Kunden-Bogen (extern): 6 Kriterien, projektweit (skill null) ─────────────
insert into public.call_criteria (id, project_id, skill, category, order_index, prompt, type, max_points, weight, allow_na, active, compliance_critical, rater_kind) values
 ('c1000000-0000-4000-8000-000000000001','proj_rw_demo',null,'Gesprächseinstieg',1,'Freundliche Begrüßung mit Namen und Firmennennung','yesno',1,1,false,true,false,'extern'),
 ('c1000000-0000-4000-8000-000000000002','proj_rw_demo',null,'Bedarf',2,'Bedarf sauber ermittelt (Ziel, Zeitraum, Personen, Budget)','yesno',1,2,false,true,false,'extern'),
 ('c1000000-0000-4000-8000-000000000003','proj_rw_demo',null,'Angebot',3,'Passendes Angebot mit klaren Leistungen unterbreitet','yesno',1,2,false,true,false,'extern'),
 ('c1000000-0000-4000-8000-000000000004','proj_rw_demo',null,'Zusatzverkauf',4,'Zusatzleistungen angeboten (Versicherung / Transfer / Ausflüge)','yesno',1,1,true,true,false,'extern'),
 ('c1000000-0000-4000-8000-000000000005','proj_rw_demo',null,'Abschluss',5,'Verbindlicher Abschluss oder klare nächste Schritte','yesno',1,2,false,true,false,'extern'),
 ('c1000000-0000-4000-8000-000000000006','proj_rw_demo',null,'Compliance',6,'Identität und Datenschutz korrekt geprüft','yesno',1,1,false,true,true,'extern');

insert into public.call_score_config (id, project_id, skill, green_min, yellow_min, threshold_unit, feedback_green, feedback_amber, feedback_red, rater_kind) values
 ('c2000000-0000-4000-8000-000000000001','proj_rw_demo',null,85,70,'percent','Sehr gutes Gespräch, weiter so.','Solide, mit Luft nach oben bei Bedarf und Abschluss.','Bitte Gesprächsleitfaden nachschärfen.','extern');

-- ── Beispiel-Bewertungen (extern) für 3 Agenten: grün / gelb / rot ───────────
insert into public.call_samples (id, employee_id, sampled_date, kw, year, project_id, skill, criteria_scope, note, total_pct, status, conducted_by_name, conducted_at, total_points, max_points, compliance_failed, rater_kind) values
 ('c3000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001',date '2026-09-05',36,2026,'proj_rw_demo','reise','project','Buchung Ägypten-Paket, sehr souverän.',92,'done','Reisewelt QM',timestamptz '2026-09-05 11:00+00',8.5,9,false,'extern'),
 ('c3000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000003',date '2026-09-06',36,2026,'proj_rw_demo','reise','project','Beratung Kreta, Abschluss etwas zögerlich.',78,'done','Reisewelt QM',timestamptz '2026-09-06 14:30+00',7,9,false,'extern'),
 ('c3000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000005',date '2026-09-07',37,2026,'proj_rw_demo','reise','project','Bedarf nicht vollständig erhoben.',64,'done','Reisewelt QM',timestamptz '2026-09-07 09:15+00',5.5,9,false,'extern');

-- ── Kunde ↔ Team Chat ────────────────────────────────────────────────────────
insert into public.client_team_messages (project_id, from_side, author_name, body, sent_at) values
 ('proj_rw_demo','client','Reisewelt','Guten Morgen! Können wir die Erreichbarkeit am Wochenende kurz besprechen?', timestamptz '2026-09-08 08:12+00'),
 ('proj_rw_demo','team','Teamleitung','Gerne. Für Samstag haben wir zwei Agenten zusätzlich eingeplant.', timestamptz '2026-09-08 09:03+00'),
 ('proj_rw_demo','client','Reisewelt','Perfekt. Und wie läuft der neue Umbuchungsprozess an?', timestamptz '2026-09-09 10:20+00'),
 ('proj_rw_demo','team','Teamleitung','Die Kurzanleitung ist verteilt, die Schulung ist für nächste Woche geplant.', timestamptz '2026-09-09 10:35+00');

-- ── Reisewelt-Kundenkonto ────────────────────────────────────────────────────
insert into public.client_accounts (id, company_name, company_legal, industry, project_name, project_id, contact_name, contact_email, billing_model, billing_currency, login_email, active, must_change_pw, visible_tabs)
values ('client_rw_demo','Reisewelt','Reisewelt Touristik GmbH','Pauschalreisen','Reisewelt','proj_rw_demo','Sabine Vogt','kunde@reisewelt.example','per_agent','EUR','kunde@reisewelt.example',true,false,
        ARRAY['overview','employees','orgchart','shifts','quality','messages','arbeitsplan'])
on conflict (id) do update set visible_tabs=excluded.visible_tabs, project_id=excluded.project_id, active=true, must_change_pw=false;
