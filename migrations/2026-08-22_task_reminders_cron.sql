-- Schnitt 5a: Cron fuer task-reminders. Feuert zu 6 UTC-Stunden, die Edge Function sendet nur, wenn es in
-- Europe/Berlin 09/12/16 Uhr ist (Ortszeit-Pruefung in der Function -> DST-sicher, genau ein Versand je Slot).
do $$ begin
  if exists (select 1 from cron.job where jobname='task-reminders') then perform cron.unschedule('task-reminders'); end if;
end $$;
select cron.schedule('task-reminders', '0 7,8,10,11,14,15 * * *', $cmd$
  select net.http_post(
    url     := 'https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/task-reminders',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'edge_service_role_key')
    ),
    body    := '{}'::jsonb
  );
$cmd$);
