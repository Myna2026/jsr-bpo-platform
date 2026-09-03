-- Jobmesse-Dispatcher minütlich; er entscheidet selbst (armed, Tagesfenster, next_send_at), ob dieser Tick
-- sendet. Dadurch unregelmäßige Abstände (6-14 Min) + schwankende Batch-Größe (15-30). Gatet auf den
-- Trigger-Key (Secret CAMPAIGN_KEY); echter Key NICHT im Repo, zum Einspielen <CAMPAIGN_KEY> ersetzen.
create extension if not exists pg_cron; create extension if not exists pg_net;
do $$ begin if exists (select 1 from cron.job where jobname='jobfair-dispatch') then perform cron.unschedule('jobfair-dispatch'); end if; end $$;
select cron.schedule('jobfair-dispatch', '* * * * *', $job$
  select net.http_post(
    url     := 'https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/jobfair-mailer',
    headers := jsonb_build_object('Content-Type','application/json','apikey','sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl'),
    body    := jsonb_build_object('key','<CAMPAIGN_KEY>','mode','dispatch')
  );
$job$);
