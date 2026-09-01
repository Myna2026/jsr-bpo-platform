-- Sales-Akquise Ausbau, Schnitt D: Nachfass-Strecke. Config (Kette + Rhythmus, anpassbar) + täglicher Cron,
-- der die Edge Function sales-followup anstößt. Sie sendet fälligen Leads die NÄCHSTE Stufe (verhaltensbasiert).

insert into public.app_config(key,value) values ('jsr_sales_followup_v1', jsonb_build_object(
  'cadence', jsonb_build_object('opened_days',3,'cold_days',7),   -- geöffnet → nach 3 Tagen, nie reagiert → nach 7
  'chain', jsonb_build_object('erstansprache','nachfass1','nachfass1','nachfass2','nachfass2','letzter','letzter',null)
)) on conflict (key) do nothing;

-- Täglich 07:30 UTC (nach der Tot-Erkennung um 06:00). --no-verify-jwt → Publishable-Key als Bearer, kein Secret.
select cron.unschedule('sales-followup-daily') where exists (select 1 from cron.job where jobname='sales-followup-daily');
select cron.schedule('sales-followup-daily', '30 7 * * *', $cmd$
select net.http_post(
  url:='https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/sales-followup',
  headers:='{"Content-Type":"application/json","Authorization":"Bearer sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl"}'::jsonb,
  body:='{}'::jsonb);
$cmd$);
