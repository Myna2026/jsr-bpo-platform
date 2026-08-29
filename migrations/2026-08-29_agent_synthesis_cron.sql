-- Vorhaben 4: die Synthese läuft täglich nach agent-observe (05:30 UTC) um 06:00 UTC (~08:00 Berlin).
-- --no-verify-jwt -> der Bearer-Wert ist egal (Publishable-Key, kein Secret).
select cron.schedule('agent-synthesis', '0 6 * * *', $cmd$
select net.http_post(
  url:='https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/agent-synthesis',
  headers:='{"Content-Type":"application/json","Authorization":"Bearer sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl"}'::jsonb,
  body:='{}'::jsonb);
$cmd$);
