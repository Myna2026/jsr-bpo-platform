-- Echte Agenten-Kommunikation (agent-dialogue) läuft täglich nach agent-observe (05:30 UTC) um 06:00 UTC.
-- Löst agent-synthesis ab (das den Faden erfand); der alte Cron wird abbestellt, die Function bleibt vorerst.
-- --no-verify-jwt -> der Bearer-Wert ist egal (Publishable-Key, kein Secret).
select cron.unschedule('agent-synthesis') where exists (select 1 from cron.job where jobname='agent-synthesis');

select cron.schedule('agent-dialogue', '0 6 * * *', $cmd$
select net.http_post(
  url:='https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/agent-dialogue',
  headers:='{"Content-Type":"application/json","Authorization":"Bearer sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl"}'::jsonb,
  body:='{}'::jsonb);
$cmd$);
