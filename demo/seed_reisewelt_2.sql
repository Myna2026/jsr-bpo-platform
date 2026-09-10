-- ═══════════════════════════════════════════════════════════════════════════
-- DEMO-SEED „Reisewelt" — TEIL 2: Schichten, KPI-Werte, Lena-Wissen, Chat
-- ═══════════════════════════════════════════════════════════════════════════
-- NUR im getrennten DEMO-Projekt (Myna) einspielen, NIE im echten System.
-- Setzt Teil 1 voraus (Projekt proj_rw_demo, 12 Personen, KPI-Definitionen, Lena).
-- Abschnitte: 5) Schichten (4 Wo)  6) KPI-Werte (5 Wo, gute+schlechte)
--             7) Lena-Wissen (4 Zielgebiete + Fälle)  8) Interner Chat
-- 9) Demo-Logins = eigener Schritt (auth-Schema, wenn Myna wach ist).
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 5) Schichtplan: 4 Wochen (Mo–Fr) für die 10 Agenten ────────────────────
-- Rotierende Schicht je Tag/Person: Früh / Mitte / Spät. 8 Nettostunden, 0,5 Pause.
delete from public.shift_assignments where project_id='proj_rw_demo';
insert into public.shift_assignments
 (project_id, skill, employee_id, work_date, label, shift_value, net_hours, gross_hours, shift, updated_by_name, updated_at)
select 'proj_rw_demo','reise', e.id, g.d::date, sh.lbl, sh.sv, 8, 8.5,
       jsonb_build_object('label',sh.lbl,'shift',sh.sv), 'Demo-Seed', now()
from (values
  ('a0000000-0000-4000-8000-000000000001'::uuid,0),('a0000000-0000-4000-8000-000000000002'::uuid,1),
  ('a0000000-0000-4000-8000-000000000003'::uuid,2),('a0000000-0000-4000-8000-000000000004'::uuid,0),
  ('a0000000-0000-4000-8000-000000000005'::uuid,1),('a0000000-0000-4000-8000-000000000006'::uuid,2),
  ('a0000000-0000-4000-8000-000000000007'::uuid,0),('a0000000-0000-4000-8000-000000000008'::uuid,1),
  ('a0000000-0000-4000-8000-000000000009'::uuid,2),('a0000000-0000-4000-8000-000000000010'::uuid,0)
) e(id,idx)
cross join generate_series(date '2026-09-14', date '2026-10-09', interval '1 day') g(d)
cross join lateral (select
   case (((g.d::date - date '2026-09-14') + e.idx) % 3) when 0 then 'Früh' when 1 then 'Mitte' else 'Spät' end as lbl,
   case (((g.d::date - date '2026-09-14') + e.idx) % 3) when 0 then '08:00-16:30' when 1 then '09:00-17:30' else '11:30-20:00' end as sv
) sh
where extract(isodow from g.d) < 6;   -- Mo–Fr

-- ── 6) KPI-Werte: 5 Wochen je Agent (CSAT/AHT/Conversion), gute UND schlechte ─
-- base = Grundniveau, trend = wöchentliche Entwicklung (jüngste Woche am besten).
delete from public.kpi_entries where emp_id in (
  'a0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000002',
  'a0000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000004',
  'a0000000-0000-4000-8000-000000000005','a0000000-0000-4000-8000-000000000006',
  'a0000000-0000-4000-8000-000000000007','a0000000-0000-4000-8000-000000000008',
  'a0000000-0000-4000-8000-000000000009','a0000000-0000-4000-8000-000000000010');
insert into public.kpi_entries (emp_id, kw, year, kpi_id, value, entered_by, ts, source)
select v.emp, extract(week from w.d)::int, extract(isoyear from w.d)::int, v.kpi,
       round((v.base + (2 - w.n) * v.trend)::numeric, 1), 'Demo-Seed', now(), 'demo'
from (values
 -- Arben (stark)          Blerina (CSAT hoch, Conv schwach)   Driton (Conv top, AHT schlecht)
 ('a0000000-0000-4000-8000-000000000001'::uuid,'kpi_rw_csat',91,0.4),('a0000000-0000-4000-8000-000000000001'::uuid,'kpi_rw_aht',5.2,-0.2),('a0000000-0000-4000-8000-000000000001'::uuid,'kpi_rw_conv',34,0.4),
 ('a0000000-0000-4000-8000-000000000002'::uuid,'kpi_rw_csat',93,0.3),('a0000000-0000-4000-8000-000000000002'::uuid,'kpi_rw_aht',6.8,-0.2),('a0000000-0000-4000-8000-000000000002'::uuid,'kpi_rw_conv',26,0.3),
 ('a0000000-0000-4000-8000-000000000003'::uuid,'kpi_rw_csat',82,0.3),('a0000000-0000-4000-8000-000000000003'::uuid,'kpi_rw_aht',9.5,-0.3),('a0000000-0000-4000-8000-000000000003'::uuid,'kpi_rw_conv',37,0.4),
 -- Fjolla (neu, schwach)  Gentian (ausgewogen)                 Learta (stark)
 ('a0000000-0000-4000-8000-000000000004'::uuid,'kpi_rw_csat',76,0.5),('a0000000-0000-4000-8000-000000000004'::uuid,'kpi_rw_aht',8.5,-0.4),('a0000000-0000-4000-8000-000000000004'::uuid,'kpi_rw_conv',20,0.5),
 ('a0000000-0000-4000-8000-000000000005'::uuid,'kpi_rw_csat',87,0.3),('a0000000-0000-4000-8000-000000000005'::uuid,'kpi_rw_aht',6.0,-0.2),('a0000000-0000-4000-8000-000000000005'::uuid,'kpi_rw_conv',30,0.3),
 ('a0000000-0000-4000-8000-000000000006'::uuid,'kpi_rw_csat',92,0.3),('a0000000-0000-4000-8000-000000000006'::uuid,'kpi_rw_aht',4.9,-0.1),('a0000000-0000-4000-8000-000000000006'::uuid,'kpi_rw_conv',33,0.3),
 -- Mentor (CSAT hoch, AHT kritisch) Rina (mittel)               Valon (mittel)
 ('a0000000-0000-4000-8000-000000000007'::uuid,'kpi_rw_csat',90,0.3),('a0000000-0000-4000-8000-000000000007'::uuid,'kpi_rw_aht',10.5,-0.4),('a0000000-0000-4000-8000-000000000007'::uuid,'kpi_rw_conv',29,0.3),
 ('a0000000-0000-4000-8000-000000000008'::uuid,'kpi_rw_csat',88,0.3),('a0000000-0000-4000-8000-000000000008'::uuid,'kpi_rw_aht',7.2,-0.2),('a0000000-0000-4000-8000-000000000008'::uuid,'kpi_rw_conv',24,0.3),
 ('a0000000-0000-4000-8000-000000000009'::uuid,'kpi_rw_csat',85,0.3),('a0000000-0000-4000-8000-000000000009'::uuid,'kpi_rw_aht',6.4,-0.2),('a0000000-0000-4000-8000-000000000009'::uuid,'kpi_rw_conv',31,0.3),
 -- Yllka (solide, Conv schwach)
 ('a0000000-0000-4000-8000-000000000010'::uuid,'kpi_rw_csat',89,0.3),('a0000000-0000-4000-8000-000000000010'::uuid,'kpi_rw_aht',5.8,-0.2),('a0000000-0000-4000-8000-000000000010'::uuid,'kpi_rw_conv',23,0.4)
) v(emp,kpi,base,trend)
cross join (select n, (date '2026-09-07' - n*7)::date d from generate_series(0,4) n) w;

-- ── 7) Lenas Wissen (Partner-Wissensbasis Reisewelt) ───────────────────────
delete from public.kb_facts where project_id='proj_rw_demo';
delete from public.kb_chunks where project_id='proj_rw_demo';
delete from public.kb_documents where project_id='proj_rw_demo';

insert into public.kb_documents (id, project_id, title, doc_kind, summary, status)
values ('d0000000-0000-4000-8000-0000000000d1','proj_rw_demo','Reiseleitung Reisewelt — Abläufe & Zielgebiete','ablauf',
        'Transfer, Umbuchung, Stornierung und Zielgebiets-Infos (Ägypten, Side, Kreta, Paris).','active');

insert into public.kb_chunks (id, document_id, project_id, ord, section, content) values
 ('c0000000-0000-4000-8000-0000000000c1','d0000000-0000-4000-8000-0000000000d1','proj_rw_demo',1,'Transfer nicht gefunden',
   'Findet ein Kunde am Flughafen den Transfer nicht, zunächst den Treffpunkt des Zielgebiets nennen (Schild „Reisewelt" am Ausgang der Ankunftshalle). Ist dort niemand, die örtliche Agentur unter der Notfallnummer des Zielgebiets anrufen. Der Kunde soll am Treffpunkt warten, der Fahrer kommt innerhalb von 30 Minuten.'),
 ('c0000000-0000-4000-8000-0000000000c2','d0000000-0000-4000-8000-0000000000d1','proj_rw_demo',2,'Umbuchung',
   'Umbuchungen von Pauschalreisen im Buchungssystem unter „Umbuchung" mit dem neuen Datum. Die Preisdifferenz wird automatisch berechnet. Zusätzlich die Hotelverfügbarkeit für den neuen Zeitraum prüfen; ist das Hotel nicht verfügbar, ein Alternativhotel gleicher Kategorie anbieten (Ersatzhotel-Liste je Zielgebiet).'),
 ('c0000000-0000-4000-8000-0000000000c3','d0000000-0000-4000-8000-0000000000d1','proj_rw_demo',3,'Stornierung',
   'Kostenfreie Stornierung bei Pauschalreisen bis 30 Tage vor Abreise. Danach gestaffelte Stornogebühren: bis 15 Tage 40 Prozent, bis 7 Tage 60 Prozent, danach 80 Prozent. Umbuchung ist oft günstiger als Stornierung und sollte zuerst angeboten werden.'),
 ('c0000000-0000-4000-8000-0000000000c4','d0000000-0000-4000-8000-0000000000d1','proj_rw_demo',4,'Ägypten Einreise',
   'Für Ägypten benötigen Reisende ein Visum, das online oder bei Ankunft erhältlich ist (Kosten ca. 25 USD). Der Reisepass muss bei Einreise noch mindestens 6 Monate gültig sein.');

insert into public.kb_facts (id, project_id, topic, zielgebiet, info_type, label, value, source, source_locator, confidence, status) values
 (gen_random_uuid(),'proj_rw_demo','Notfallnummer','Ägypten / Hurghada','kontakt','Agentur vor Ort','Sunrise Tours, +20 100 555 1010','manual','Reiseleitung','confirmed','active'),
 (gen_random_uuid(),'proj_rw_demo','Treffpunkt','Ägypten / Hurghada','ablauf','Treffpunkt Flughafen','Schild „Reisewelt" am Ausgang der Ankunftshalle, Halle B','manual','Reiseleitung','confirmed','active'),
 (gen_random_uuid(),'proj_rw_demo','Notfallnummer','Side','kontakt','Agentur vor Ort','Antalya Reisen, +90 532 444 2020','manual','Reiseleitung','confirmed','active'),
 (gen_random_uuid(),'proj_rw_demo','Treffpunkt','Side','ablauf','Treffpunkt Flughafen','Ausgang Ankunft Antalya, Counter 12','manual','Reiseleitung','confirmed','active'),
 (gen_random_uuid(),'proj_rw_demo','Notfallnummer','Kreta / Heraklion','kontakt','Agentur vor Ort','Kreta Travel, +30 694 333 3030','manual','Reiseleitung','confirmed','active'),
 (gen_random_uuid(),'proj_rw_demo','Treffpunkt','Kreta / Heraklion','ablauf','Treffpunkt Flughafen','Ausgang Ankunft Heraklion, Bereich Reiseleiter','manual','Reiseleitung','confirmed','active'),
 (gen_random_uuid(),'proj_rw_demo','Notfallnummer','Paris','kontakt','Ansprechpartner vor Ort','Paris City Guide, +33 6 12 34 56 78','manual','Reiseleitung','confirmed','active'),
 (gen_random_uuid(),'proj_rw_demo','Ablauf','Paris','ablauf','Städtereise-Check-in','Kein Flughafentransfer; Anreise individuell, Hotel-Check-in ab 15:00','manual','Reiseleitung','confirmed','active'),
 (gen_random_uuid(),'proj_rw_demo','Stornierung',null,'regel','Kostenfreie Stornofrist','Bis 30 Tage vor Abreise kostenlos, danach 40/60/80 Prozent gestaffelt','manual','Reiseleitung / Stornierung','confirmed','active'),
 (gen_random_uuid(),'proj_rw_demo','Umbuchung',null,'ablauf','Umbuchung Pauschalreise','Im Buchungssystem unter „Umbuchung", Preisdifferenz automatisch, Hotelverfügbarkeit prüfen','manual','Reiseleitung / Umbuchung','confirmed','active'),
 (gen_random_uuid(),'proj_rw_demo','Einreise','Ägypten / Hurghada','regel','Visum & Pass','Visum bei Ankunft ca. 25 USD, Reisepass 6 Monate gültig','manual','Reiseleitung / Ägypten','confirmed','active');

-- Geografische Zuordnung (Insel/Region -> Ort), damit „Problem auf Kreta" die Heraklion-Fakten findet.
delete from public.kb_regions where project_id='proj_rw_demo';
insert into public.kb_regions (project_id, name, kind, aliases, members, source, status) values
 ('proj_rw_demo','Kreta','insel','{Crete}','{"Kreta / Heraklion"}','manuell','active');

-- ── 8) Interner Chat: Team ↔ Teamleitung ↔ Back Office ─────────────────────
delete from public.dm_messages where thread_id='b0000000-0000-4000-8000-0000000000b1';
delete from public.dm_participants where thread_id='b0000000-0000-4000-8000-0000000000b1';
delete from public.dm_threads where id='b0000000-0000-4000-8000-0000000000b1';

insert into public.dm_threads (id, is_group, name, dm_key, created_at, updated_at)
values ('b0000000-0000-4000-8000-0000000000b1', true, 'Team Reisewelt', 'grp_rw_team', now(), now());

insert into public.dm_participants (thread_id, emp_id, my_lang, see_lang, joined_at)
select 'b0000000-0000-4000-8000-0000000000b1', id, 'de', 'de', now()
from public.employees where project_id='proj_rw_demo';

insert into public.dm_messages (id, thread_id, from_emp_id, text_original, lang_original, sent_at) values
 (gen_random_uuid(),'b0000000-0000-4000-8000-0000000000b1','a0000000-0000-4000-8000-000000000004','Wie mache ich eine Umbuchung für eine Side-Reise, wenn der Kunde eine Woche später fliegen will?','de', now() - interval '3 hours'),
 (gen_random_uuid(),'b0000000-0000-4000-8000-0000000000b1','a0000000-0000-4000-8000-000000000011','Im Buchungssystem unter „Umbuchung" das neue Datum wählen, die Differenz wird automatisch berechnet. Bei Pauschalreisen zusätzlich die Hotelverfügbarkeit prüfen.','de', now() - interval '2 hours 50 minutes'),
 (gen_random_uuid(),'b0000000-0000-4000-8000-0000000000b1','a0000000-0000-4000-8000-000000000004','Und wenn das Hotel im neuen Zeitraum nicht verfügbar ist?','de', now() - interval '2 hours 45 minutes'),
 (gen_random_uuid(),'b0000000-0000-4000-8000-0000000000b1','a0000000-0000-4000-8000-000000000011','Dann ein Alternativhotel gleicher Kategorie anbieten. Dafina hat die Ersatzhotel-Liste.','de', now() - interval '2 hours 40 minutes'),
 (gen_random_uuid(),'b0000000-0000-4000-8000-0000000000b1','a0000000-0000-4000-8000-000000000012','Liste liegt im Wiki unter „Side / Ersatzhotels". Achtung: die Ägypten-Stornofrist ist neu, bei Fragen meldet euch.','de', now() - interval '2 hours 30 minutes'),
 (gen_random_uuid(),'b0000000-0000-4000-8000-0000000000b1','a0000000-0000-4000-8000-000000000002','Kurze Rückfrage: Notfallnummer Kreta? Kundin steht am Flughafen und findet den Transfer nicht.','de', now() - interval '1 hour'),
 (gen_random_uuid(),'b0000000-0000-4000-8000-0000000000b1','a0000000-0000-4000-8000-000000000012','Frag Lena, die hat die Nummer und den Treffpunkt sofort parat. 🙂','de', now() - interval '55 minutes');

-- Ende Teil 2. Offen: 9) Demo-Logins (auth-Schema) als eigener Schritt, sobald Myna wach ist.
