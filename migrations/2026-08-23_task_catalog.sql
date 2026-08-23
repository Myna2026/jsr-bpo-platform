-- Aufgaben-Katalog in die DB (EINE Wahrheit statt Duplikat hr.html + task-reminders). Frontend UND Edge
-- Function lesen ab jetzt task_catalog. Additiv; Seed autogeneriert aus dem bisherigen ROLE_TASKS (exakt).
create table if not exists public.task_catalog (
  key text primary key,
  seq int not null default 0,
  owner text[] not null,
  title text not null,
  descr text,
  view_key text,
  count_key text,
  cadence text,
  window_weeks int[],
  auto_key text,
  nav jsonb,
  active boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.task_catalog enable row level security;
drop policy if exists task_catalog_sel on public.task_catalog;
drop policy if exists task_catalog_write on public.task_catalog;
create policy task_catalog_sel on public.task_catalog for select to authenticated using (true);
create policy task_catalog_write on public.task_catalog for all to authenticated using (is_management()) with check (is_management());
grant select, insert, update, delete on public.task_catalog to authenticated;

insert into public.task_catalog(key,seq,owner,title,descr,view_key,count_key,cadence,window_weeks,auto_key,nav) values
('mgr_checkin', 10, array['management','teamlead','projektleiter']::text[], 'Check-in: Anwesenheit bestätigen', 'Für die heute eingeteilten Mitarbeiter bestätigen, wer da ist. Ein Klick „Da", die Uhrzeit wird automatisch erfasst, die Verspätung ermittelt das System. Krank oder „kommt nicht mehr" im zweiten Schritt. Wer es morgens nicht macht, dem fehlt der Ist-Stand für den Tag.', 'checkin', 'checkin_open', null, null, null, null),
('mgr_cv_abgleich', 20, array['management']::text[], 'CV-Abgleich HR', 'Mit HR abgleichen, dass eingegangene CVs erfasst und in der richtigen Phase sind.', 'kanban', null, null, null, null, null),
('mgr_cv_funnel', 30, array['management']::text[], 'CV-Funnel prüfen', 'Den Bewerber-Funnel im Blick behalten: bleibt kein Kandidat in einer Phase liegen?', 'kanban', 'cv_funnel', null, null, null, null),
('mgr_kunden', 40, array['management']::text[], 'Kundentelefonate & Wochen-Updates', 'Die fälligen Kundentermine und Wochen-Updates führen (Termine im Kalender).', 'calendar', 'customer_due', null, null, null, null),
('mgr_kpi', 50, array['management']::text[], 'KPI-Pflege je Skill', 'Sicherstellen, dass die KPIs je Skill/Projekt für den Zeitraum gepflegt sind.', 'performance', 'kpi_missing', 'weekly', null, null, null),
('mgr_rechnung', 60, array['management']::text[], 'Rechnungserstellung', 'Rechnungen für den Vormonat erstellen (Buchhaltung tive-finance).', null, null, null, array[1]::int[], 'invoice_create', null),
('mgr_lohn', 70, array['management']::text[], 'Lohnlauf & Überweisung', 'Lohnlauf durchführen und Überweisung veranlassen.', 'payroll', 'payroll_open', null, array[1]::int[], 'payroll', null),
('hr_cv_select', 80, array['hr']::text[], 'Eingehende CVs selektieren', 'Neue Lebensläufe sichten und selektieren.', 'cvs', 'cv_inbound', null, null, null, '{"type":"cv_inbox","label":"Bewerbungen"}'::jsonb),
('hr_cv_phase', 90, array['hr']::text[], 'CVs in die richtige Phase', 'Bewerber in die passende Funnel-Phase schieben, damit keiner liegen bleibt.', 'kanban', 'cv_stuck', null, null, null, null),
('hr_kommunikation', 100, array['hr']::text[], 'Bewerber-Kommunikation', 'Neue Eingänge und laufende Bewerber kontaktieren.', 'cvs', 'cv_comm', null, null, null, null),
('hr_interview', 110, array['hr']::text[], 'Vorstellungsgespräche', 'Die anstehenden Vorstellungsgespräche führen.', 'kanban', 'cv_interview', null, null, null, null),
('hr_stammdaten', 120, array['hr']::text[], 'Stammdatenpflege', 'Kontakt, Bankverbindung und Adresse der Mitarbeiter aktuell halten.', 'employees', 'emp_no_iban', 'weekly', null, null, null),
('hr_vertraege', 130, array['hr']::text[], 'Arbeitsverträge', 'Verträge erstellen und pflegen, auf auslaufende achten.', 'employees', 'contract_gap', 'weekly', null, null, null),
('hr_hardware', 140, array['hr']::text[], 'Hardware-Koordination', 'Hardware-Ausgabe und -Rückgabe koordinieren.', 'employees', 'hw_missing', 'weekly', null, null, null),
('hr_onboarding', 150, array['hr']::text[], 'Onboarding-Pflege', 'Onboarding der neuen Mitarbeiter aktuell halten.', 'onboarding', 'onboarding_open', null, null, null, null),
('hr_feedback', 160, array['hr']::text[], 'Mitarbeitergespräche', 'Die heutigen Feedbackgespräche ziehen und führen.', 'feedback', 'feedback_open', null, null, null, null),
('hr_bonus', 170, array['hr']::text[], 'Bonuspflege', 'Boni je Mitarbeiter für den Monat pflegen.', 'employees', 'bonus_missing', null, array[1,2]::int[], null, null),
('fin_re_in', 180, array['finance']::text[], 'Rechnungseingang', 'Eingehende Rechnungen erfassen (tive-finance).', null, null, null, null, null, null),
('fin_re_out', 190, array['finance']::text[], 'Rechnungsausgang', 'Ausgehende Rechnungen erfassen (tive-finance).', null, null, null, null, null, null),
('fin_buchungen', 200, array['finance']::text[], 'Buchungen Buchhaltung', 'Laufende Buchungen in der Buchhaltung (tive-finance).', null, null, null, null, null, null),
('fin_lohn', 210, array['finance']::text[], 'Gehaltsabrechnung & Löhne', 'Gehaltsabrechnung erstellen und Löhne vorbereiten.', 'payroll', 'payroll_open', null, array[1]::int[], 'payroll', null),
('fin_bwa', 220, array['finance']::text[], 'Monatsabschluss BWA', 'Monatsabschluss und BWA erstellen (tive-finance).', null, null, null, array[1,2]::int[], null, null),
('lead_shift', 230, array['projektleiter','teamlead']::text[], 'Schichtplan aktuell halten', 'Die kommenden Tage einplanen, damit keine offenen Tage bleiben. Wer wann auf welchem Skill sitzt, gehört vor den Tag festgelegt.', 'shiftplan', null, null, null, null, null),
('lead_absence', 240, array['projektleiter','teamlead']::text[], 'Abwesenheiten & Krankmeldungen', 'Krankmeldungen (Anruf bis 8:30) eintragen und die heutigen Abwesenheiten prüfen, damit die Besetzung stimmt.', 'absences', null, null, null, null, null),
('lead_vacreq', 250, array['projektleiter','teamlead']::text[], 'Urlaubsanträge entscheiden', 'Offene Urlaubsanträge deines Teams entscheiden (Grün/Gelb/Rot). Du kennst die Besetzung, darum entscheidest du, nicht HR.', 'urlaubantraege', 'vacreq_open', null, null, null, null),
('pl_kpi', 260, array['projektleiter']::text[], 'Kennzahlen des Projekts pflegen', 'Die KPIs für Projekt und Skill der Woche pflegen, damit Auswertungen und Kundenbericht stimmen.', 'performance', 'kpi_missing', 'weekly', null, null, null),
('pl_perf', 270, array['projektleiter']::text[], 'Team-Performance prüfen', 'Wöchentlich die Rangliste im Blick behalten: wer läuft gut, wer braucht Unterstützung.', 'performance', null, 'weekly', null, null, null),
('pl_bericht', 280, array['projektleiter']::text[], 'Wochenbericht vorbereiten', 'Die Präsentation bzw. den Wochenbericht für den Kundentermin aktuell halten.', 'praesentation', null, 'weekly', null, null, null)
on conflict (key) do update set seq=excluded.seq, owner=excluded.owner, title=excluded.title, descr=excluded.descr, view_key=excluded.view_key, count_key=excluded.count_key, cadence=excluded.cadence, window_weeks=excluded.window_weeks, auto_key=excluded.auto_key, nav=excluded.nav, updated_at=now();
