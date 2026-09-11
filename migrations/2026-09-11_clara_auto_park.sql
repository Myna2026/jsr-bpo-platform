-- =============================================================================
-- Clara Auto-Parken: parkt taeglich Bewerber, die in den FRUEHPHASEN
-- (cv_inbound=Eingang, cv_confirmed=Terminvereinbarung, invited=Telefoninterview)
-- laenger als die eingestellte Frist unbearbeitet liegen -> Status 'pool'
-- (Vorrat, keine Absage, keine Mail). Spaetere Phasen (interview/selection2/
-- contract/training...) bleiben unberuehrt.
--
-- "Unbearbeitet" = coalesce(last_worked_at, created_at) (ehrlicher Menschen-Stempel,
-- siehe 2026-09-11_cvs_last_worked_at.sql). Backfill = Stichtag -> beim Einschalten
-- wird der bestehende Berg NICHT sofort geparkt.
--
-- Steuerung in jsr_clara_auto_v1.auto_park { enabled, idle_days }. Off by default.
-- Idempotent.
-- =============================================================================

create extension if not exists pg_cron;

-- 1) Default-Konfiguration (nur anlegen, bestehende Einstellung nicht ueberschreiben).
update public.app_config
   set value = jsonb_set(value, '{auto_park}',
        jsonb_build_object('enabled', false, 'idle_days', 10), true)
 where key = 'jsr_clara_auto_v1'
   and not (value ? 'auto_park');

-- 2) Die Parkfunktion. SECURITY DEFINER (Cron laeuft ohne JWT). Guard: nur wenn enabled.
--    parked_from haelt die Ursprungsphase (fuer "Zurueckholen"); parked_at das Datum.
create or replace function public.clara_auto_park()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg jsonb; en boolean; days int; today text := ((now() at time zone 'Europe/Berlin')::date)::text;
  parked int; byphase jsonb;
begin
  select value into cfg from public.app_config where key = 'jsr_clara_auto_v1';
  en   := coalesce((cfg->'auto_park'->>'enabled')::boolean, false);
  days := greatest(1, coalesce((cfg->'auto_park'->>'idle_days')::int, 10));
  if not en then
    return jsonb_build_object('skipped', true, 'reason', 'disabled');
  end if;

  with cand as (
    select id, status
      from public.cvs
     where status in ('cv_inbound','cv_confirmed','invited')
       and coalesce(last_worked_at, created_at) < now() - make_interval(days => days)
  ),
  upd as (
    update public.cvs c
       set status = 'pool',
           extra  = coalesce(c.extra, '{}'::jsonb)
                    || jsonb_build_object('parked_reason','idle','parked_at', today, 'parked_from', c.status)
      from cand
     where c.id = cand.id
     returning cand.status as from_status
  )
  select count(*)::int, coalesce(jsonb_object_agg(from_status, cnt), '{}'::jsonb)
    from (select from_status, count(*) cnt from upd group by from_status) t
    into parked, byphase;

  parked := coalesce(parked, 0);
  -- Letzte Ausfuehrung festhalten (fuer Anzeige/Meldung in der Clara-Steuerung + Pool).
  update public.app_config
     set value = jsonb_set(value, '{auto_park,last_run}',
          jsonb_build_object('at', now(), 'parked', parked, 'by_phase', byphase, 'idle_days', days), true)
   where key = 'jsr_clara_auto_v1';

  return jsonb_build_object('parked', parked, 'by_phase', byphase, 'at', now());
end $$;
revoke all on function public.clara_auto_park() from public;

-- 3) Taeglicher Cron 05:40 UTC (~07:40 Europe/Berlin). Laeuft gefahrlos: die Funktion parkt nur, wenn
--    auto_park.enabled=true. Vorher meldet sie nur 'skipped'.
do $$ begin
  if exists (select 1 from cron.job where jobname='clara-auto-park') then
    perform cron.unschedule('clara-auto-park');
  end if;
end $$;
select cron.schedule('clara-auto-park', '40 5 * * *', $job$ select public.clara_auto_park(); $job$);
