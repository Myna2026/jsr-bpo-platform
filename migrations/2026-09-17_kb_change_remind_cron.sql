-- Cron: Erinnerung/Eskalation für offene Wissensänderungen (Funktion prüft selbst Zeitfenster 08 Uhr Berlin, Werktag).
select cron.unschedule('kb-change-remind') where exists (select 1 from cron.job where jobname='kb-change-remind');
select cron.schedule('kb-change-remind', '0 * * * *', $$
      select net.http_post(url := 'https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/kb-change-remind',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl','apikey','sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl'),
        body := '{}'::jsonb); $$);
