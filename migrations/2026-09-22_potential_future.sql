-- Recruiting-Phase „Potenzial Zukunft“ (User 2026-09-22): bewusste Entscheidung für gute Bewerber, die jetzt nicht
-- starten, mit Wiedervorlage-Datum und Grund. NICHT der Pool (dort parkt Clara automatisch Liegengebliebenes).
-- „Ruhend“ (parking) wird abgelöst: die Bestandsfälle wandern mit Wiedervorlage in 3 Monaten hierher.
-- Felder in cvs.extra: future_due (YYYY-MM-DD), future_reason (Satz), future_from (Herkunftsphase), future_target (optional),
-- future_set_at / future_set_by.
alter table public.cvs drop constraint if exists cvs_status_valid;
alter table public.cvs add constraint cvs_status_valid check (status = any (array[
  'cv_inbound','cv_accepted','cv_confirmed','invited','interview','selection1','selection2','selected','contract',
  'training_planned','training','active','inactive','parking','pool','potential_future',
  'rejected_by_us','rejected_by_employee','rejected_by_client','no_contact','homeoffice_only','incomplete','blacklist',
  'already_employee','converted','terminated','freigestellt_bezahlt','freigestellt_unbezahlt']));

-- Bestand „Ruhend“ übernehmen: Wiedervorlage in 3 Monaten, Grund „aus Ruhend übernommen“.
update public.cvs
   set status = 'potential_future',
       status_changed_at = now(),
       extra = coalesce(extra,'{}'::jsonb) || jsonb_build_object(
         'future_due', to_char((now() at time zone 'Europe/Berlin')::date + 90, 'YYYY-MM-DD'),
         'future_reason', 'aus Ruhend übernommen',
         'future_from', coalesce(extra->>'parked_from', 'cv_inbound'),
         'future_set_at', to_char(now() at time zone 'Europe/Berlin', 'YYYY-MM-DD"T"HH24:MI:SS'),
         'future_set_by', 'Übernahme Ruhend')
 where status = 'parking';
