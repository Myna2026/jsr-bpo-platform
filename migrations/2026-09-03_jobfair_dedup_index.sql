-- Härtung gegen Doppelversand (Wettlauf paralleler Dispatcher-Läufe, 2026-09-03):
-- 1+2) einmalige Bereinigung bereits entstandener Doppel-Einträge (frühesten je Bewerber behalten),
-- 3) eindeutiger Index: je Bewerber höchstens EIN jobfair-Eintrag -> Doppelversand DB-seitig unmöglich.
--    Der Dispatcher legt den Eintrag jetzt VOR dem Senden an; kollidiert der Insert, überspringt er.
delete from public.applicant_messages t using (
  select id, row_number() over (partition by cv_id order by sent_at asc nulls last, ctid asc) rn
  from public.applicant_messages where purpose='jobfair'
) d where t.id=d.id and d.rn>1;

delete from public.mail_messages t using (
  select id, row_number() over (partition by cv_id order by occurred_at asc, ctid asc) rn
  from public.mail_messages where mailbox='recruiting' and direction='out' and subject like 'Jobmesse%' and cv_id is not null
) d where t.id=d.id and d.rn>1;

create unique index if not exists applicant_messages_jobfair_cv_uq on public.applicant_messages(cv_id) where purpose='jobfair';
