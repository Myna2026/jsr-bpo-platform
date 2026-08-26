select cron.schedule('agent-observe','30 5 * * *',$$
select net.http_post(
  url:='https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/agent-observe',
  headers:='{"Content-Type":"application/json","Authorization":"Bearer SERVICE_ROLE_KEY"}'::jsonb,
  body:='{}'::jsonb);
$$);
