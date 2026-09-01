-- Sales-Akquise: Versand-Rhythmus. Kein Massenversand aus dem neuen Postfach, sondern verteilt (Drip) mit Aufwärmphase.
-- Config (einstellbar wie der Nachfass-Rhythmus) + Zustand (next_send_at). Der Dispatcher läuft minütlich, sendet aber
-- nur zufällig alle 3-7 Min ein bis zwei Mails im Zeitfenster. Er übernimmt AUCH die Nachfasser → alter Batch-Cron raus.

insert into public.app_config(key,value) values ('jsr_sales_pace_v1', jsonb_build_object(
  'gap_min_minutes', 3, 'gap_max_minutes', 7,     -- Abstand zufällig in dieser Spanne (nicht exakt alle 5 Min)
  'batch_min', 1, 'batch_max', 2,                 -- eine oder zwei Mails je Versand
  'hour_start', 8, 'hour_end', 17,                -- Zeitfenster (lokal)
  'days', jsonb_build_array(1,2,3,4,5),           -- Mo-Fr (1=Mo)
  'timezone', 'Europe/Berlin',
  'warmup_start', '2026-09-01',                   -- Start der Aufwärmphase (neues Postfach)
  'warmup_days', 14, 'warmup_cap', 25,            -- erste 2 Wochen höchstens 25/Tag
  'ramp_days', 14                                 -- danach über 2 Wochen hoch auf den vollen Tages-Deckel
)) on conflict (key) do nothing;

insert into public.app_config(key,value) values ('jsr_sales_pace_state_v1', jsonb_build_object('next_send_at', null))
  on conflict (key) do nothing;

-- Nachfass-Batch-Cron abschalten: der Dispatcher verteilt die Nachfasser jetzt mit.
select cron.unschedule('sales-followup-daily') where exists (select 1 from cron.job where jobname='sales-followup-daily');

-- Dispatcher minütlich; er entscheidet selbst (Zeitfenster, Abstand, Deckel), ob dieser Tick sendet.
select cron.unschedule('sales-dispatch') where exists (select 1 from cron.job where jobname='sales-dispatch');
select cron.schedule('sales-dispatch', '* * * * *', $cmd$
select net.http_post(
  url:='https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/sales-dispatch',
  headers:='{"Content-Type":"application/json","Authorization":"Bearer sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl"}'::jsonb,
  body:='{}'::jsonb);
$cmd$);
