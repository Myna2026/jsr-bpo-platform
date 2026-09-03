-- 5-Minuten-Takt fuer den Postfach-Eingang: ruft die Edge Function mail-fetch, die neue Mails aus
-- recruiting@25hrs.net in mail_messages spiegelt und Bewerbern zuordnet. mail-fetch gatet auf den
-- Trigger-Key (Secret CAMPAIGN_KEY); der echte Key steht NICHT im Repo. Zum Einspielen <CAMPAIGN_KEY>
-- ersetzen (oder die bereits gescharfte /tmp-Variante nutzen), im Supabase-SQL-Editor ausfuehren.
--
-- Kontrolle:  select jobname, schedule, active from cron.job where jobname='mail-fetch-recruiting';
-- Laeufe:     select * from cron.job_run_details where command like '%mail-fetch%' order by start_time desc limit 5;

create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$ begin
  if exists (select 1 from cron.job where jobname='mail-fetch-recruiting') then perform cron.unschedule('mail-fetch-recruiting'); end if;
end $$;

select cron.schedule('mail-fetch-recruiting', '*/5 * * * *', $job$
  select net.http_post(
    url     := 'https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/mail-fetch',
    headers := jsonb_build_object('Content-Type','application/json','apikey','sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl'),
    body    := jsonb_build_object('key','<CAMPAIGN_KEY>')
  );
$job$);
