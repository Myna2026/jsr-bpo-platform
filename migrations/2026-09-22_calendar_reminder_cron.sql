-- Kalender-Erinnerung alle 5 Minuten prüfen (die Function sendet nur im Fenster 15 bis 10 Minuten vor Beginn
-- und schreibt den Anspruch vorher, deshalb kein Doppelversand).
select cron.unschedule('calendar-reminder') where exists (select 1 from cron.job where jobname='calendar-reminder');
select cron.schedule('calendar-reminder', '*/5 * * * *', $$
      select net.http_post(url := 'https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/calendar-reminder',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl','apikey','sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl'),
        body := '{}'::jsonb); $$);
