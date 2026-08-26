select cron.schedule('clara-digest','0 5,6 * * *',$$
select net.http_post(
  url:='https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/clara-digest',
  headers:='{"Content-Type":"application/json","Authorization":"Bearer SERVICE_ROLE_KEY"}'::jsonb,
  body:='{}'::jsonb);
$$);
