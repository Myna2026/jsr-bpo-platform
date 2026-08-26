-- Täglicher Maya-Lauf: fasst den Vortag je aktivem Nutzer zusammen (Edge Function usage-digest, leerer Body
-- = gestern). ~05:00 Europe/Berlin = 03:00 UTC, damit die Sätze morgens ohne Knopfdruck bereitstehen.
-- ERST BEIM GO-LIVE ausführen (Supabase-SQL-Editor). <PROJECT_REF>/<SERVICE_ROLE_KEY> eintragen, Key NICHT committen.

create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
begin
  if exists (select 1 from cron.job where jobname='usage-digest-daily') then
    perform cron.unschedule('usage-digest-daily');
  end if;
end $$;

select cron.schedule('usage-digest-daily', '0 3 * * *', $job$
  select net.http_post(
    url     := 'https://<PROJECT_REF>.supabase.co/functions/v1/usage-digest',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer <SERVICE_ROLE_KEY>'),
    body    := '{}'::jsonb
  );
$job$);

-- Vault-Variante (empfohlen): 'Bearer '||(select decrypted_secret from vault.decrypted_secrets where name='service_role_key')
-- Kontrolle:  select jobname, schedule, active from cron.job where jobname='usage-digest-daily';
