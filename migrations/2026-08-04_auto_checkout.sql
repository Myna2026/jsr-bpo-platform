-- =============================================================================
-- Auto-Check-out: departure serverseitig festschreiben (pg_cron)         2026-08-04
-- =============================================================================
-- Wenn die geplante Schicht vorbei ist, gilt ein eingecheckter Mitarbeiter als
-- ausgecheckt. Die Anzeige leitet das live ab (Zeile verschwindet); die IST-Zeit
-- (`departure`) MUSS aber zuverlässig persistiert werden, sonst fehlt sie beim
-- späteren Plan-vs-Ist. Client-seitig wäre das lückenhaft (nur wenn jemand die
-- Ansicht öffnet) — deshalb ein täglicher DB-Job.
--
-- Regel: für Check-ins des Zieltags mit Status da/verspätet/früher OHNE departure
-- wird departure = geplantes Schichtende gesetzt. Geplantes Ende = GRÖSSTES HH:MM
-- im Schicht-Text der zugehörigen shift_assignments-Zelle (Split-Schicht → letztes
-- Ende, wie gewünscht).
--
-- Zeitplan: 02:00 UTC (= 03:00/04:00 CET) und verarbeitet den VORTAG (Europe/Berlin),
-- also den vollständig abgeschlossenen Tag — DST-sicher.
--
-- Voraussetzung: pg_cron aktiviert (Supabase: einmal `create extension pg_cron`).
-- Idempotent. Im Supabase SQL-Editor ausführen.
-- =============================================================================

create extension if not exists pg_cron;

-- ── Kern: setzt departure für einen Tag; gibt die Anzahl geschriebener Zeilen zurück ──
create or replace function public.auto_checkout_daily(target date default null)
returns integer language plpgsql security definer set search_path=public as $$
declare d date; n integer;
begin
  d := coalesce(target, (now() at time zone 'Europe/Berlin')::date);
  with planned as (
    select sc.project_id, sc.skill, sc.employee_id, sc.work_date, sc.source,
           (select max((mm[1])::time)
              from regexp_matches(
                     concat_ws(' ', sa.shift_value, sa.label,
                               sa.shift->>'shift', sa.shift->>'label',
                               sa.shift->>'split_morning', sa.shift->>'split_afternoon'),
                     '(\d{1,2}:\d{2})', 'g') as mm) as end_t
    from public.shift_checkins sc
    join public.shift_assignments sa
      on  sa.project_id  = sc.project_id
      and sa.skill       = sc.skill
      and sa.employee_id = sc.employee_id
      and sa.work_date   = sc.work_date
    where sc.work_date = d
      and sc.departure is null
      and sc.status in ('present','late','early')
  )
  update public.shift_checkins sc
     set departure = p.end_t, updated_at = now()
    from planned p
   where sc.project_id  = p.project_id
     and sc.skill       = p.skill
     and sc.employee_id = p.employee_id
     and sc.work_date   = p.work_date
     and sc.source      = p.source
     and p.end_t is not null;
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.auto_checkout_daily(date) from public;
-- Nur der Cron-Owner ruft die Funktion; kein authenticated-Grant nötig.

-- ── Täglicher Zeitplan (VORTAG, 02:00 UTC) ───────────────────────────────────
-- Bestehenden Job gleichen Namens vorher entfernen (idempotent; 0 Zeilen falls keiner da).
select cron.unschedule(jobid) from cron.job where jobname = 'auto-checkout-daily';

select cron.schedule('auto-checkout-daily', '0 2 * * *',
  $$ select public.auto_checkout_daily( ((now() at time zone 'Europe/Berlin')::date - 1) ); $$);

-- ── Prüfen / manuell nachholen (optional) ────────────────────────────────────
-- select public.auto_checkout_daily(current_date - 1);   -- gestern manuell festschreiben
-- select jobname, schedule, active from cron.job where jobname='auto-checkout-daily';
