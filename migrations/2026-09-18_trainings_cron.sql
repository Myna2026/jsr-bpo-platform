-- Schulungen: Miriams Ebenen für neue geprüfte Fragen nachts nachziehen (nach coach-generate). 04:40 Uhr, eine Portion je Partner.
select cron.unschedule('training-enrich') where exists (select 1 from cron.job where jobname='training-enrich');
select cron.schedule('training-enrich', '40 4 * * *', $$
      select net.http_post(url := 'https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/training-enrich',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl','apikey','sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl'),
        body := '{"limit":40}'::jsonb); $$);
