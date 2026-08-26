-- Lenas Chat-Wächter im Takt: ruft die Edge Function chat-watch (Stichwort-Vorfilter -> KI nur bei Verdacht).
-- Alle 3 Minuten. ERST BEIM GO-LIVE ausführen (Supabase-SQL-Editor). <SERVICE_ROLE_KEY> eintragen, nicht committen.
create extension if not exists pg_cron;
create extension if not exists pg_net;
select cron.schedule('chat-watch', '*/3 * * * *', $$
  select net.http_post(
    url := 'https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/chat-watch',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer SERVICE_ROLE_KEY'),
    body := '{}'::jsonb);
$$);
