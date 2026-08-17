-- Täglicher Bewerber-Import (Meta + Google-Sheet) um 02:00 UTC, nach dem Windsor-Lauf (01:00 UTC).
-- Ruft die Edge Function applicant-import mit dem Service-Role-Key auf. Braucht pg_cron + pg_net (Supabase).
-- WICHTIG: <PROJECT_REF> und <SERVICE_ROLE_KEY> eintragen. Den Service-Key NICHT ins Repo committen
-- (dieses SQL nur im Supabase-SQL-Editor ausfuehren). Sauberer: Key aus Vault ziehen (Variante unten).

create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
begin
  if exists (select 1 from cron.job where jobname='applicant-import-daily') then
    perform cron.unschedule('applicant-import-daily');
  end if;
end $$;

select cron.schedule('applicant-import-daily', '0 2 * * *', $job$
  select net.http_post(
    url     := 'https://<PROJECT_REF>.supabase.co/functions/v1/applicant-import',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer <SERVICE_ROLE_KEY>'),
    body    := '{}'::jsonb
  );
$job$);

-- Variante mit Vault (empfohlen): Service-Key als Secret 'service_role_key' hinterlegen, dann:
--   select vault.create_secret('<SERVICE_ROLE_KEY>', 'service_role_key');
-- und im cron.schedule statt des Klartext-Keys:
--   'Bearer '||(select decrypted_secret from vault.decrypted_secrets where name='service_role_key')

-- Kontrolle:  select jobname, schedule, active from cron.job where jobname='applicant-import-daily';
-- Laeufe:     select * from cron.job_run_details order by start_time desc limit 5;
