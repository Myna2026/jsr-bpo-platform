-- =============================================================================
-- Stempeluhr: server-autoritatives Stempeln per PIN via RPC          2026-07-19
-- =============================================================================
-- Etappe ST2: SECURITY-DEFINER-Funktionen lookup_pin() + stamp_by_pin(). Das Kiosk-
-- Tablet hat KEINEN Login -> Aufruf als anon. Die Funktionen laufen als Owner und
-- umgehen RLS -> time_pins (PIN-Liste) und employees werden NIE direkt exponiert;
-- der Client bekommt nur das Noetige (Name, Status, Session-Zustand) zurueck.
--
-- Voraussetzung: 2026-07-18_timetracking.sql (time_sessions) + 2026-07-19_time_pins.sql.
-- Idempotent (create or replace / create table if not exists / drop policy if exists).
-- Anzuwenden im Supabase SQL Editor (hier NICHT ausgefuehrt).
--
-- BRUTE-FORCE-SCHUTZ (globale Sperre, nicht pro PIN):
--   Ein PIN ist nur 4-stellig (10.000 Kombis). Eine PRO-PIN-Sperre waere durch
--   Durchprobieren VERSCHIEDENER Codes trivial zu umgehen. Darum zaehlen wir
--   Fehlversuche GLOBAL ueber ein rollierendes 5-Minuten-Fenster:
--     * Jeder Fehlversuch (unbekannter Code) -> 1 Zeile in time_pin_attempts.
--     * Vor jeder Aktion: count(Fehlversuche der letzten 5 min). Ab >= 5 ist das
--       gesamte Terminal gesperrt (auch gueltige PINs), bis die aeltesten Fehlversuche
--       aus dem Fenster herausfallen (self-healing, kein Cron noetig).
--   Zusaetzlich respektiert wird eine OPTIONALE Pro-PIN-Sperre (time_pins.locked_until),
--   die HR/Management manuell setzen kann (harte Einzelsperre) — sie wird zuerst geprueft.
--   time_pin_attempts speichert NUR Zeitstempel (kein Code, kein Name) -> kein Datenleck;
--   alte Zeilen werden beim Schreiben opportunistisch geloescht.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1 Fehlversuch-Log (nur Zeitstempel; Basis der globalen Sperre)
-- -----------------------------------------------------------------------------
create table if not exists public.time_pin_attempts (
  id           uuid primary key default gen_random_uuid(),
  attempted_at timestamptz default now()
);
create index if not exists idx_time_pin_attempts_at on public.time_pin_attempts(attempted_at);
-- Kein Direktzugriff: RLS an, KEINE Policy -> nur die SECURITY-DEFINER-Funktionen (Owner) lesen/schreiben.
alter table public.time_pin_attempts enable row level security;


-- -----------------------------------------------------------------------------
-- §2 lookup_pin(p_code) — PIN pruefen, Person + Session-Zustand zurueckgeben
-- -----------------------------------------------------------------------------
create or replace function public.lookup_pin(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fails  int;
  v_oldest timestamptz;
  v_pin    time_pins%rowtype;
  v_emp    employees%rowtype;
  v_sess   time_sessions%rowtype;
  v_today  date := current_date;
begin
  -- 1) Globale Rate-Limit-Sperre: >= 5 Fehlversuche in den letzten 5 Minuten?
  select count(*), min(attempted_at) into v_fails, v_oldest
    from time_pin_attempts where attempted_at > now() - interval '5 minutes';
  if v_fails >= 5 then
    return jsonb_build_object('error','locked','reason','rate_limit',
      'retry_after_seconds', greatest(1, ceil(extract(epoch from (v_oldest + interval '5 minutes' - now())))::int));
  end if;

  -- 2) PIN suchen
  select * into v_pin from time_pins where code = p_code;

  -- 2a) Optionale Pro-PIN-Sperre zuerst respektieren
  if found and v_pin.locked_until is not null and v_pin.locked_until > now() then
    return jsonb_build_object('error','locked','reason','pin_locked','until', v_pin.locked_until);
  end if;

  -- 2b) Unbekannter Code -> Fehlversuch protokollieren (+ alte Zeilen aufraeumen)
  if not found then
    delete from time_pin_attempts where attempted_at < now() - interval '1 hour';
    insert into time_pin_attempts default values;
    return jsonb_build_object('error','invalid');
  end if;

  -- 3) Mitarbeiter + Status
  select * into v_emp from employees where id = v_pin.emp_id;
  if not found then
    return jsonb_build_object('error','invalid');
  end if;
  if v_emp.status not in ('active','training') then
    return jsonb_build_object('error','inactive','status', v_emp.status);
  end if;

  -- Erfolg: Pro-PIN-Zaehler zuruecksetzen
  update time_pins set failed_attempts = 0, locked_until = null, updated_at = now()
    where emp_id = v_pin.emp_id;

  -- 4) Heutige Session (laufende bevorzugt)
  select * into v_sess from time_sessions
    where emp_id = v_pin.emp_id and session_date = v_today
    order by (clock_out is null) desc, created_at desc limit 1;

  return jsonb_build_object(
    'emp_name', trim(coalesce(v_emp.first_name,'') || ' ' || coalesce(v_emp.last_name,'')),
    'staff_number', v_emp.staff_number,
    'status', v_emp.status,
    'session', case when v_sess.id is null then null else jsonb_build_object(
      'id', v_sess.id, 'clock_in', v_sess.clock_in, 'clock_out', v_sess.clock_out,
      'pause_active', v_sess.pause_active, 'smoke_active', v_sess.smoke_active,
      'pauses', coalesce(v_sess.pauses,'[]'::jsonb), 'smokes', coalesce(v_sess.smokes,'[]'::jsonb)) end
  );
end;
$$;


-- -----------------------------------------------------------------------------
-- §3 stamp_by_pin(p_code, p_action) — Stempelung ausfuehren (bildet stamp() ab)
-- -----------------------------------------------------------------------------
-- Zeiten in Ortszeit (Tirana/Prishtina == Europe/Berlin-Offset) als 'HH:MM'.
create or replace function public.stamp_by_pin(p_code text, p_action text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fails  int;
  v_pin    time_pins%rowtype;
  v_emp    employees%rowtype;
  v_sess   time_sessions%rowtype;
  v_today  date := current_date;
  v_now    text := to_char(now() at time zone 'Europe/Berlin', 'HH24:MI');
  v_inm    int; v_outm int; v_gross int; v_pmin int; v_smin int; v_net int;
  v_start  text; v_dur int; v_name text;
begin
  -- Rate-Limit
  select count(*) into v_fails from time_pin_attempts where attempted_at > now() - interval '5 minutes';
  if v_fails >= 5 then
    return jsonb_build_object('ok',false,'error','locked','reason','rate_limit');
  end if;

  -- PIN + Sperre + MA/Status
  select * into v_pin from time_pins where code = p_code;
  if not found then
    delete from time_pin_attempts where attempted_at < now() - interval '1 hour';
    insert into time_pin_attempts default values;
    return jsonb_build_object('ok',false,'error','invalid');
  end if;
  if v_pin.locked_until is not null and v_pin.locked_until > now() then
    return jsonb_build_object('ok',false,'error','locked','reason','pin_locked','until',v_pin.locked_until);
  end if;
  select * into v_emp from employees where id = v_pin.emp_id;
  if not found or v_emp.status not in ('active','training') then
    return jsonb_build_object('ok',false,'error','inactive');
  end if;
  v_name := trim(coalesce(v_emp.first_name,'') || ' ' || coalesce(v_emp.last_name,''));

  -- heutige Session (laufende bevorzugt)
  select * into v_sess from time_sessions
    where emp_id = v_pin.emp_id and session_date = v_today
    order by (clock_out is null) desc, created_at desc limit 1;

  if p_action = 'in' then
    if v_sess.id is not null and v_sess.clock_out is null then
      return jsonb_build_object('ok',false,'error','already_in');
    end if;
    insert into time_sessions(emp_id, session_date, clock_in, clock_out, pauses, smokes)
      values (v_pin.emp_id, v_today, v_now, null, '[]'::jsonb, '[]'::jsonb)
      returning * into v_sess;

  elsif v_sess.id is null or v_sess.clock_out is not null then
    return jsonb_build_object('ok',false,'error','not_clocked_in');

  elsif p_action = 'out' then
    v_inm  := split_part(v_sess.clock_in,':',1)::int*60 + split_part(v_sess.clock_in,':',2)::int;
    v_outm := split_part(v_now,':',1)::int*60 + split_part(v_now,':',2)::int;
    v_gross := greatest(0, v_outm - v_inm);
    select coalesce(sum((e->>'duration')::int),0) into v_pmin from jsonb_array_elements(coalesce(v_sess.pauses,'[]'::jsonb)) e;
    select coalesce(sum((e->>'duration')::int),0) into v_smin from jsonb_array_elements(coalesce(v_sess.smokes,'[]'::jsonb)) e;
    v_net := greatest(0, v_gross - v_pmin - v_smin);
    update time_sessions set clock_out = v_now, pause_active = null, smoke_active = null,
      hours = round(v_net/6.0)/10.0, hours_gross = round(v_gross/6.0)/10.0,
      pause_total = v_pmin, smoke_total = v_smin
      where id = v_sess.id returning * into v_sess;

  elsif p_action = 'pause_start' then
    if v_sess.pause_active is not null or v_sess.smoke_active is not null then
      return jsonb_build_object('ok',false,'error','busy');
    end if;
    update time_sessions set pause_active = v_now where id = v_sess.id returning * into v_sess;

  elsif p_action = 'pause_end' then
    if v_sess.pause_active is null then return jsonb_build_object('ok',false,'error','no_pause'); end if;
    v_start := v_sess.pause_active;
    v_dur := greatest(0, (split_part(v_now,':',1)::int*60 + split_part(v_now,':',2)::int)
                       - (split_part(v_start,':',1)::int*60 + split_part(v_start,':',2)::int));
    update time_sessions set pause_active = null,
      pauses = coalesce(v_sess.pauses,'[]'::jsonb) || jsonb_build_array(jsonb_build_object('start',v_start,'end',v_now,'duration',v_dur))
      where id = v_sess.id returning * into v_sess;

  elsif p_action = 'smoke_start' then
    if v_sess.pause_active is not null or v_sess.smoke_active is not null then
      return jsonb_build_object('ok',false,'error','busy');
    end if;
    update time_sessions set smoke_active = v_now where id = v_sess.id returning * into v_sess;

  elsif p_action = 'smoke_end' then
    if v_sess.smoke_active is null then return jsonb_build_object('ok',false,'error','no_smoke'); end if;
    v_start := v_sess.smoke_active;
    v_dur := greatest(0, (split_part(v_now,':',1)::int*60 + split_part(v_now,':',2)::int)
                       - (split_part(v_start,':',1)::int*60 + split_part(v_start,':',2)::int));
    update time_sessions set smoke_active = null,
      smokes = coalesce(v_sess.smokes,'[]'::jsonb) || jsonb_build_array(jsonb_build_object('start',v_start,'end',v_now,'duration',v_dur))
      where id = v_sess.id returning * into v_sess;

  else
    return jsonb_build_object('ok',false,'error','bad_action');
  end if;

  return jsonb_build_object('ok',true,'emp_name',v_name,'action',p_action,'time',v_now,
    'session_state', jsonb_build_object(
      'id', v_sess.id, 'clock_in', v_sess.clock_in, 'clock_out', v_sess.clock_out,
      'pause_active', v_sess.pause_active, 'smoke_active', v_sess.smoke_active,
      'pauses', coalesce(v_sess.pauses,'[]'::jsonb), 'smokes', coalesce(v_sess.smokes,'[]'::jsonb),
      'hours', v_sess.hours, 'hours_gross', v_sess.hours_gross));
end;
$$;


-- -----------------------------------------------------------------------------
-- §4 Grants — anon (Kiosk ohne Login) + authenticated duerfen NUR die RPCs aufrufen
-- -----------------------------------------------------------------------------
revoke all on function public.lookup_pin(text)            from public;
revoke all on function public.stamp_by_pin(text, text)    from public;
grant execute on function public.lookup_pin(text)         to anon, authenticated;
grant execute on function public.stamp_by_pin(text, text) to anon, authenticated;


-- =============================================================================
-- Verifikation (auskommentiert)
-- =============================================================================
-- (a) Beide Funktionen SECURITY DEFINER:
--     select proname, prosecdef from pg_proc where proname in ('lookup_pin','stamp_by_pin'); -- prosecdef=t
-- (b) anon darf ausfuehren:
--     select has_function_privilege('anon','public.lookup_pin(text)','execute');             -- t
-- (c) time_pin_attempts: RLS an, 0 Policies (nur Definer-Zugriff):
--     select relrowsecurity, (select count(*) from pg_policy where polrelid='public.time_pin_attempts'::regclass)
--       from pg_class where relname='time_pin_attempts';                                      -- t | 0
-- (d) Funktions-Smoke-Test:
--     select public.lookup_pin('9999');       -- {"error":"invalid"} (bzw. Person)
--     select public.stamp_by_pin('1234','in');-- {"ok":true,...} bei gueltigem PIN
-- =============================================================================
