-- Takt fuer den HolidayCheck-Report und Pauls Waechter.
-- Die Functions entscheiden selbst, ob ihr Fenster dran ist (Berliner Zeit), damit die Uhrzeit
-- ueber die Zeitumstellung richtig bleibt. Der Cron klopft nur alle fuenf Minuten an; die Stunden
-- sind UTC und grosszuegig gesetzt (13:00 Berlin = 11:00 UTC, 19:15/19:25 Berlin = 17:15/17:25 UTC).
select cron.schedule('hc-report', '*/5 10-12,16-18 * * *', $cron$
  select net.http_post(url := 'https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/hc-report',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl','apikey','sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl'),
    body := '{}'::jsonb);
$cron$);

select cron.schedule('hc-watch', '*/5 17-18 * * *', $cron$
  select net.http_post(url := 'https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/hc-watch',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl','apikey','sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl'),
    body := '{}'::jsonb);
$cron$);

-- Beide Jobs stehen zunaechst AUF PAUSE: erst wenn der Eigentuemer die Testmails freigegeben hat und
-- die Forecast-Frage mit HolidayCheck geklaert ist, sollen Zahlen an Thorsten und Rajner gehen.
-- Scharfschalten: select cron.alter_job((select jobid from cron.job where jobname='hc-report'), active := true);
select cron.alter_job((select jobid from cron.job where jobname='hc-report'), active := false);
select cron.alter_job((select jobid from cron.job where jobname='hc-watch'),  active := false);

select jobname, schedule, active from cron.job where jobname like 'hc-%' order by jobname;
