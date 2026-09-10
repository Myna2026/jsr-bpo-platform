-- Schnitt 2 (Personen-Zeitwahrheit): Statushistorie fuer Mitarbeiter.
-- Ziel: Kopfzahlen wie "Aktiv"/"Schulung" fuer einen VERGANGENEN Zeitraum korrekt zaehlen (heute nur Live-Bestand).
-- Muster: Von-Bis-Perioden pro Mitarbeiter, gepflegt an EINER Stelle (DB-Trigger auf employees) statt an 8 UI-Wegen.
-- Halb-offene Intervalle [from_date, to_date): to_date=null bedeutet laufend. Ein Statuswechsel am Tag D schliesst
-- die alte Periode bei D und oeffnet die neue ab D (as-of D = neuer Status).
--
-- Ehrlichkeit (Vorgabe des Users): AB der Migration tagesgenau (Trigger), DAVOR nur geschaetzt (Backfill aus
-- Datums-Ankern). Der Cutover-Tag steht in app_config.status_history_exact_since; Schnitt 3 badget As-of-Daten
-- davor als "geschaetzt". Es werden KEINE nicht belegten Vergangenheits-Uebergaenge erfunden (activity_log hat
-- nur 34 Status-Diffs ab 22.07. und deckt z.B. den Juni gar nicht ab).

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Tabelle
create table if not exists public.employee_status_periods (
  id           bigint generated always as identity primary key,
  employee_id  uuid not null references public.employees(id) on delete cascade,
  status       text not null,
  from_date    date not null,
  to_date      date,                                  -- null = laufend
  source       text not null default 'trigger',       -- 'trigger' | 'backfill_flat'
  changed_by   uuid,
  created_at   timestamptz not null default now(),
  constraint esp_range_ok check (to_date is null or to_date >= from_date)
);
create index if not exists idx_esp_emp  on public.employee_status_periods(employee_id, from_date);
create index if not exists idx_esp_asof on public.employee_status_periods(from_date, to_date);
-- Invariante: hoechstens EINE offene Periode je Mitarbeiter.
create unique index if not exists uq_esp_one_open on public.employee_status_periods(employee_id) where to_date is null;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) Trigger-Funktion: pflegt die Perioden bei INSERT und bei Statuswechsel (UPDATE OF status).
create or replace function public.esp_track_status()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_from date; v_open record;
begin
  if TG_OP = 'INSERT' then
    v_from := coalesce(nullif(NEW.contract->>'start','')::date, NEW.hire_date, current_date);
    insert into public.employee_status_periods(employee_id, status, from_date, source)
      values (NEW.id, NEW.status, v_from, 'trigger');
    return NEW;
  end if;
  -- UPDATE OF status
  if NEW.status is not distinct from OLD.status then return NEW; end if;
  select * into v_open from public.employee_status_periods
    where employee_id = NEW.id and to_date is null order by from_date desc limit 1;
  if found then
    if v_open.from_date >= current_date then
      -- Wechsel am selben Tag (oder offene Periode in der Zukunft): kein Null-Intervall, nur Status korrigieren.
      update public.employee_status_periods set status = NEW.status where id = v_open.id;
      return NEW;
    end if;
    update public.employee_status_periods set to_date = current_date where id = v_open.id;
  end if;
  insert into public.employee_status_periods(employee_id, status, from_date, source)
    values (NEW.id, NEW.status, current_date, 'trigger');
  return NEW;
end $$;

drop trigger if exists trg_esp_ins on public.employees;
create trigger trg_esp_ins after insert on public.employees
  for each row execute function public.esp_track_status();
drop trigger if exists trg_esp_upd on public.employees;
create trigger trg_esp_upd after update of status on public.employees
  for each row execute function public.esp_track_status();

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) Backfill (einmalig, nur wenn Tabelle leer) — flache Schaetzung aus den Datums-Ankern.
--    Nicht-gekuendigt: eine offene Periode [start, null) mit dem aktuellen Status.
--    Gekuendigt (termination_date gesetzt): Arbeitsspanne [start, term) als 'active' (geschaetzt, damit
--    Ex-Mitarbeiter in vergangenen Monaten als aktiv zaehlen) + offene Periode [term, null) mit aktuellem Status.
do $$
begin
  if (select count(*) from public.employee_status_periods) = 0 then
    -- nicht gekuendigt → offene Periode, aktueller Status
    insert into public.employee_status_periods(employee_id, status, from_date, to_date, source)
    select e.id, e.status,
           coalesce(nullif(e.contract->>'start','')::date, e.hire_date, current_date), null, 'backfill_flat'
    from public.employees e
    where e.termination_date is null;

    -- gekuendigt → Arbeitsspanne 'active' (geschaetzt), nur wenn start < term
    insert into public.employee_status_periods(employee_id, status, from_date, to_date, source)
    select e.id, 'active',
           coalesce(nullif(e.contract->>'start','')::date, e.hire_date, e.termination_date), e.termination_date, 'backfill_flat'
    from public.employees e
    where e.termination_date is not null
      and coalesce(nullif(e.contract->>'start','')::date, e.hire_date, e.termination_date) < e.termination_date;

    -- gekuendigt → offene Endperiode ab term mit aktuellem Status (terminated/freigestellt_*)
    insert into public.employee_status_periods(employee_id, status, from_date, to_date, source)
    select e.id, e.status, e.termination_date, null, 'backfill_flat'
    from public.employees e
    where e.termination_date is not null;

    -- Cutover-Marker: ab HEUTE tagesgenau, davor geschaetzt.
    insert into public.app_config(key, value)
      values ('status_history_exact_since', to_jsonb(current_date::text))
    on conflict (key) do nothing;
  end if;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) As-of-Abfrage: welcher Status hatte jeder Mitarbeiter am Stichtag p_date. Security-Definer, damit die
--    Kennzahlen-Ebene (Schnitt 3) sie aufrufen kann, ohne die Rohtabelle breit zu oeffnen.
create or replace function public.employee_status_on(p_date date)
returns table(employee_id uuid, status text)
language sql stable security definer set search_path=public as $$
  select distinct on (p.employee_id) p.employee_id, p.status
  from public.employee_status_periods p
  where p.from_date <= p_date and (p.to_date is null or p.to_date > p_date)
  order by p.employee_id, p.from_date desc
$$;
grant execute on function public.employee_status_on(date) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5) RLS: nur Admins (management/hr/finance) lesen die Rohperioden direkt; Schreiben nur ueber den Trigger.
alter table public.employee_status_periods enable row level security;
drop policy if exists esp_read on public.employee_status_periods;
create policy esp_read on public.employee_status_periods for select to authenticated
  using (public.is_management() or public.is_hr() or public.is_finance());

notify pgrst, 'reload schema';
