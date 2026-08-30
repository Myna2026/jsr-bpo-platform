-- Maya System-Watch: Scan täglich (05:50 UTC), Digest-Mail Dienstag + Freitag (07:00 UTC).
-- --no-verify-jwt -> Bearer-Wert egal (Publishable-Key, kein Secret).
select cron.unschedule('maya-system-scan')   where exists (select 1 from cron.job where jobname='maya-system-scan');
select cron.unschedule('maya-system-digest') where exists (select 1 from cron.job where jobname='maya-system-digest');

select cron.schedule('maya-system-scan', '50 5 * * *', $cmd$
select net.http_post(
  url:='https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/maya-system-scan',
  headers:='{"Content-Type":"application/json","Authorization":"Bearer sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl"}'::jsonb,
  body:='{}'::jsonb);
$cmd$);

select cron.schedule('maya-system-digest', '0 7 * * 2,5', $cmd$
select net.http_post(
  url:='https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/maya-system-digest',
  headers:='{"Content-Type":"application/json","Authorization":"Bearer sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl"}'::jsonb,
  body:='{}'::jsonb);
$cmd$);
