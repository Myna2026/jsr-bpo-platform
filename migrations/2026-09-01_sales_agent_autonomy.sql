-- Sales-Akquise Ausbau, Schnitt F: Moritz betreibt es selbst. Autonomie-Konfig (Default KONSERVATIV: autonomer
-- Erstkontakt AUS, Moritz recherchiert + priorisiert, sendet aber nur auf Freigabe) + täglicher Orchestrator-Cron.

insert into public.app_config(key,value) values ('jsr_sales_autonomy_v1', jsonb_build_object(
  'enabled', false,              -- Gesamtschalter für autonomen Versand (Default aus)
  'auto_research', true,         -- neue Leads selbst recherchieren (harmlos, kein Versand)
  'research_cap', 10,            -- max. Recherchen je Lauf
  'auto_first_contact', true,    -- greift nur, wenn enabled=true
  'daily_cap', 15                -- max. autonome Erstkontakte je Tag
)) on conflict (key) do nothing;

-- Platzhalter für die letzte Lauf-Zusammenfassung (füllt der Orchestrator).
insert into public.app_config(key,value) values ('jsr_sales_agent_last_v1', '{}'::jsonb) on conflict (key) do nothing;

-- Täglich 07:00 UTC (vor der Nachfass-Strecke 07:30). --no-verify-jwt → Publishable-Key als Bearer.
select cron.unschedule('sales-agent-run') where exists (select 1 from cron.job where jobname='sales-agent-run');
select cron.schedule('sales-agent-run', '0 7 * * *', $cmd$
select net.http_post(
  url:='https://msdiyjxckmpvuomnhvjp.supabase.co/functions/v1/sales-agent-run',
  headers:='{"Content-Type":"application/json","Authorization":"Bearer sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl"}'::jsonb,
  body:='{}'::jsonb);
$cmd$);
