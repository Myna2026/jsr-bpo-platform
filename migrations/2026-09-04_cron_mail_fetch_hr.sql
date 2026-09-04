-- Schnitt 5: hr@-Posteingang alle 5 Minuten abrufen (wie mail-fetch-recruiting, nur mailbox:'hr').
-- Der Abruf übernimmt NUR an hr@25hrs.net adressierte Mails (Alias-Schutz gegen Deonitas Privatpost, in mail-fetch).
select cron.schedule('mail-fetch-hr', '*/5 * * * *', $cron$
  select net.http_post(
    url := 'https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/mail-fetch',
    headers := jsonb_build_object('Content-Type','application/json','apikey','sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl'),
    body := jsonb_build_object('key','8dc696d5e150474f9da260103aa40364','mailbox','hr')
  );
$cron$);
