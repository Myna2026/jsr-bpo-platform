-- Clara-Automatik Schnitt 6: Takt (Cron) + sanfter Start (Sende-Budget je Lauf).
-- Der Cron läuft gefahrlos, BEVOR scharfgeschaltet wird: der Mailer sendet nur, wenn in jsr_clara_auto_v1
-- eine Phase/ein Ausgang enabled ist UND Claras Leitplanke 'freigabe' steht. Sonst meldet er nur "skipped".
-- Werktag-/Zeitfenster-bewusst: Mo-Fr, Geschäftszeit. Absagen laufen zeitversetzt (48 h) über denselben Scan.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- (1) Sende-Budget je Lauf in die Steuerung aufnehmen (falls noch nicht vorhanden). Verhindert einen Schwall
--     aus dem Rückstau (~300 cv_inbound) beim ersten Scharfschalten und schont die Absender-Reputation.
--     In der Clara-Steuerung ohne Code änderbar.
update public.app_config
   set value = jsonb_set(value, '{max_sends_per_run}', '25'::jsonb, true)
 where key = 'jsr_clara_auto_v1'
   and not (value ? 'max_sends_per_run');

-- (2) Phasen-/Absagen-Scan: applicant-mailer im Scan-Modus. Auth über CAMPAIGN_KEY im Body (stabiler Weg,
--     unabhängig von Service-Key-Rotationen). Alle 30 Min, Mo-Fr, 06-16 UTC (≈ 07-18 Uhr Europe/Berlin).
do $$
begin
  if exists (select 1 from cron.job where jobname='applicant-mailer-scan') then
    perform cron.unschedule('applicant-mailer-scan');
  end if;
end $$;

select cron.schedule('applicant-mailer-scan', '*/30 6-16 * * 1-5', $job$
  select net.http_post(
    url     := 'https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/applicant-mailer',
    headers := jsonb_build_object('Content-Type','application/json'),
    body    := '{"mode":"scan","key":"8dc696d5e150474f9da260103aa40364"}'::jsonb
  );
$job$);

-- (3) Übergabe-Scan: legt fällige "wartet auf Deonita"-Übergaben an und löst hinfällige auf. Reine DB-Funktion,
--     kein HTTP nötig. Stündlich Mo-Fr in Geschäftszeit hält die "wartet auf dich"-Liste frisch.
do $$
begin
  if exists (select 1 from cron.job where jobname='clara-handover-scan') then
    perform cron.unschedule('clara-handover-scan');
  end if;
end $$;

select cron.schedule('clara-handover-scan', '5 6-16 * * 1-5', $job$
  select public.clara_handover_scan();
$job$);

-- Kontrolle:
--   select jobname, schedule, active from cron.job where jobname in ('applicant-mailer-scan','clara-handover-scan');
--   select * from cron.job_run_details order by start_time desc limit 5;
