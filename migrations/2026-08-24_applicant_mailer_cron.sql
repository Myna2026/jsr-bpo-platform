-- Automatik-Takt fuer den Bewerber-Mailversand: ruft die Edge Function applicant-mailer im Scan-Modus.
-- Die Function schickt NUR, wenn jsr_enrich_mail_v1.auto_enabled=true UND ein Absender scharf ist —
-- der Cron kann also gefahrlos laufen, bevor scharf geschaltet wird (er meldet dann nur "skipped").
--
-- ERST BEIM GO-LIVE ausfuehren (im Supabase-SQL-Editor). Service-Key NICHT ins Repo committen.
-- <PROJECT_REF> und <SERVICE_ROLE_KEY> eintragen (oder Vault-Variante unten).
-- Alle 30 Minuten. Bei 65 Bewerbungen/Tag reicht das locker; Intervall nach Bedarf anpassen.

create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
begin
  if exists (select 1 from cron.job where jobname='applicant-mailer-scan') then
    perform cron.unschedule('applicant-mailer-scan');
  end if;
end $$;

select cron.schedule('applicant-mailer-scan', '*/30 * * * *', $job$
  select net.http_post(
    url     := 'https://<PROJECT_REF>.supabase.co/functions/v1/applicant-mailer',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer <SERVICE_ROLE_KEY>'),
    body    := '{"mode":"scan"}'::jsonb
  );
$job$);

-- Vault-Variante (empfohlen): Service-Key als Secret 'service_role_key' hinterlegen, dann statt Klartext:
--   'Bearer '||(select decrypted_secret from vault.decrypted_secrets where name='service_role_key')
--
-- Kontrolle:  select jobname, schedule, active from cron.job where jobname='applicant-mailer-scan';
-- Laeufe:     select * from cron.job_run_details order by start_time desc limit 5;
