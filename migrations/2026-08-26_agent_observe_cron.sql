-- Cron für die Beobachtungs-Maschine (Schnitt 4): jeden Morgen 05:30 prüft jeder Kollege sein Gebiet.
-- Früh, damit die Befunde bereitliegen; die Einblende-ZEITEN (nicht 6 Uhr, nicht in der Schicht) regelt Schnitt 5.
-- SERVICE_ROLE_KEY ersetzen (nicht committen). Einmal im Supabase-SQL-Editor ausführen.
select cron.schedule('agent-observe', '30 5 * * *', $$
  select net.http_post(
    url    := 'https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/agent-observe',
    headers:= '{"Content-Type":"application/json","Authorization":"Bearer SERVICE_ROLE_KEY"}'::jsonb,
    body   := '{}'::jsonb
  );
$$);
