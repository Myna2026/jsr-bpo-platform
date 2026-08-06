-- =============================================================================
-- Check-out-Herkunft: departure_source am shift_checkins-Eintrag         2026-08-06
-- =============================================================================
-- Drei Wege schreiben dieselbe `departure`-Zeit, aber mit unterschiedlichem
-- Gewicht — deshalb eine Herkunft am Check-out (analog zur Pausen-Herkunft):
--   auto      – Nacht-Job schreibt das geplante Schichtende (Annahme)
--   manual    – jemand trägt die tatsächliche Endzeit ein (Feststellung)
--   timeclock – später über die Stempeluhr (Messung)
-- Ohne Herkunft ließe sich 16:30 später nicht als "gemessen" vs "angenommen"
-- unterscheiden.
--
-- VORRANG: manual/timeclock (Feststellung/Messung) schlagen auto (Annahme).
--   * Der Nacht-Job schreibt weiterhin NUR, wo `departure` leer ist → er
--     überschreibt eine manuelle Eintragung nie.
--   * Der manuelle Weg im Frontend überschreibt dagegen bewusst auch einen
--     bereits gesetzten auto-Wert (nachträgliche Korrektur).
--
-- Idempotent. Im Supabase SQL-Editor ausführen.
-- =============================================================================

alter table public.shift_checkins
  add column if not exists departure_source text;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'shift_checkins_depsrc_chk') then
    alter table public.shift_checkins
      add constraint shift_checkins_depsrc_chk
      check (departure_source is null or departure_source in ('auto','manual','timeclock'));
  end if;
end $$;

-- Backfill: bestehende departure-Werte stammen ausnahmslos vom Nacht-Job
-- (einen manuellen Weg gab es bis jetzt nicht).
update public.shift_checkins
   set departure_source = 'auto'
 where departure is not null and departure_source is null;

-- ── Nacht-Job aktualisiert: stempelt beim Festschreiben departure_source='auto' ──
-- (Zeitplan/cron.schedule unverändert — ruft die Funktion nur beim Namen auf.)
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
      and sc.departure is null                       -- nie eine Feststellung überschreiben
      and sc.status in ('present','late','early')
  )
  update public.shift_checkins sc
     set departure = p.end_t, departure_source = 'auto', updated_at = now()
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

-- ── Prüfen (optional) ────────────────────────────────────────────────────────
-- select departure, departure_source, count(*) from public.shift_checkins
--   group by 1,2 order by 2 nulls first;               -- Verteilung der Herkünfte
-- select public.auto_checkout_daily(current_date - 1);  -- Vortag nachholen (setzt nur leere)
