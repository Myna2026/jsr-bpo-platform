-- Coach: Fragenbank nachts je Partner nachziehen (neue Fakten/Abschnitte, veraltete Fragen erneuern). 04:10 Uhr.
select cron.unschedule('coach-generate') where exists (select 1 from cron.job where jobname='coach-generate');
select cron.schedule('coach-generate', '10 4 * * *', $$
      select net.http_post(url := 'https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/coach-generate',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl','apikey','sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl'),
        body := '{"ai_limit":20}'::jsonb); $$);
