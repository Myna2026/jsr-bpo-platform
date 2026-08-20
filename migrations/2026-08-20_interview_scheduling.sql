-- Terminvereinbarung fuer Bewerber, Schnitt 1 (Backend).
-- HR erzeugt eine Einladung (Token + Teilnehmer + angebotene Formen). Der Bewerber oeffnet einen oeffentlichen
-- Link (ohne Login, wie showcase.html), sieht freie 30-Min-Slots der naechsten 10 Werktage (nur Zeiten, die bei
-- ALLEN Teilnehmern frei sind, Bueroezeit-Fenster) und bestaetigt einen Slot + Form. Bei Bestaetigung: Eintrag
-- im Systemkalender fuer alle Teilnehmer + CV-Phase -> 'invited'. Kollisionsschutz atomar.
-- Outlook spaeter: nur interview_busy_blocks um eine zweite Belegungsquelle erweitern (UNION), sonst nichts.

begin;

-- ── Buerozeit-Konfig (im Admin aenderbar) ─────────────────────────────────────
insert into public.app_config(key, value, updated_at)
values ('jsr_interview_hours_v1',
        jsonb_build_object('start','09:00','end','18:00','weekdays', jsonb_build_array(1,2,3,4,5),
                           'slot_min',30,'window_days',10,'lead_hours',1),
        now())
on conflict (key) do nothing;

-- ── Einladungen ───────────────────────────────────────────────────────────────
create table if not exists public.interview_invites (
  id                 uuid primary key default gen_random_uuid(),
  cv_id              uuid not null references public.cvs(id) on delete cascade,
  token              text not null unique,
  participant_ids    uuid[] not null default '{}',            -- employees.id der Eingeladenen
  forms              text[] not null default '{}',            -- angeboten: 'phone' | 'teams' | 'office'
  status             text not null default 'open',            -- open | booked | expired | cancelled
  expires_at         timestamptz not null,
  booked_slot        timestamptz,
  booked_form        text,
  calendar_event_ids uuid[] default '{}',
  created_by         uuid,
  created_at         timestamptz not null default now()
);
alter table public.interview_invites enable row level security;
drop policy if exists interview_invites_read on public.interview_invites;
create policy interview_invites_read on public.interview_invites for select to authenticated
  using ( public.is_admin() or public.is_planner() );
grant select on public.interview_invites to authenticated;

-- ── Belegung je Teilnehmer aus dem Systemkalender (OUTLOOK-HAKEN) ──────────────
-- Liefert belegte Zeitbloecke (Datum + von/bis) fuer die gegebenen Teilnehmer im Zeitraum. Heute NUR
-- calendar_events (Occurrences je Wiederholung, ausgeblendete Overrides raus). Spaeter: zweite Quelle
-- (Outlook Free/Busy) per UNION ALL mit gleichem Rueckgabe-Shape anfuegen -> Slot-Rechnung bleibt unveraendert.
create or replace function public.interview_busy_blocks(p_participants uuid[], p_from date, p_to date)
returns table(busy_date date, start_time time, end_time time)
language sql stable security definer set search_path = public as $$
  select d::date, e.start_time, e.end_time
  from generate_series(p_from::timestamp, p_to::timestamp, interval '1 day') d
  join public.calendar_events e on e.participants && p_participants
  where e.start_time is not null and e.end_time is not null
    and d::date >= e.start_date
    and (e.until_date is null or d::date <= e.until_date)
    and (
         (coalesce(e.recurrence,'none') = 'none' and d::date = e.start_date)
      or (e.recurrence = 'weekly'   and (d::date - e.start_date) % 7  = 0)
      or (e.recurrence = 'biweekly' and (d::date - e.start_date) % 14 = 0)
      or (e.recurrence = 'monthly'  and extract(day from d) = extract(day from e.start_date))
    )
    and not exists (
      select 1 from public.calendar_overrides o
      where o.event_id = e.id and o.occurrence_date = d::date and o.hidden
    );
$$;

-- ── Einladung erzeugen (HR) ──────────────────────────────────────────────────
create or replace function public.create_interview_invite(p_cv_id uuid, p_participant_ids uuid[], p_forms text[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_token text; v_days int;
begin
  if not (public.is_admin() or public.is_planner()) then
    raise exception 'not authorized';
  end if;
  if not exists (select 1 from public.cvs where id = p_cv_id) then
    raise exception 'cv not found';
  end if;
  if p_participant_ids is null or array_length(p_participant_ids,1) is null then
    raise exception 'participants required';
  end if;
  if p_forms is null or array_length(p_forms,1) is null or exists (
       select 1 from unnest(p_forms) f where f not in ('phone','teams','office')) then
    raise exception 'invalid forms';
  end if;
  v_days := coalesce((select (value->>'window_days')::int from public.app_config where key='jsr_interview_hours_v1'), 10);
  v_token := replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','');
  insert into public.interview_invites(cv_id, token, participant_ids, forms, status, expires_at, created_by)
  values (p_cv_id, v_token, p_participant_ids, p_forms, 'open', now() + (v_days || ' days')::interval, auth.uid());
  return jsonb_build_object('token', v_token);
end $$;

-- ── Freie Slots fuer den Bewerber (oeffentlich, per Token) ────────────────────
create or replace function public.get_interview_slots(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  inv public.interview_invites%rowtype;
  v_name text; cfg jsonb;
  v_start time; v_end time; v_slot int; v_win int; v_lead int; v_today date;
  slots jsonb;
begin
  select * into inv from public.interview_invites where token = p_token;
  if not found then return jsonb_build_object('status','notfound'); end if;
  select nullif(trim(coalesce(first_name,'')||' '||coalesce(last_name,'')),'') into v_name from public.cvs where id = inv.cv_id;
  if inv.status = 'booked' then
    return jsonb_build_object('status','booked','applicant_name',v_name,'booked_slot',to_char(inv.booked_slot,'YYYY-MM-DD"T"HH24:MI'),'booked_form',inv.booked_form);
  end if;
  if inv.status <> 'open' or inv.expires_at < now() then
    return jsonb_build_object('status','expired','applicant_name',v_name);
  end if;
  select value into cfg from public.app_config where key = 'jsr_interview_hours_v1';
  v_start := coalesce((cfg->>'start')::time, time '09:00');
  v_end   := coalesce((cfg->>'end')::time,   time '18:00');
  v_slot  := coalesce((cfg->>'slot_min')::int, 30);
  v_win   := coalesce((cfg->>'window_days')::int, 10);
  v_lead  := coalesce((cfg->>'lead_hours')::int, 1);
  v_today := (now() at time zone 'Europe/Berlin')::date;

  with days as (
    select d::date dd
    from generate_series(v_today::timestamp, (v_today + (v_win-1))::timestamp, interval '1 day') d
    where extract(isodow from d) between 1 and 5
  ),
  times as (
    select (v_start + (n || ' minutes')::interval)::time tt
    from generate_series(0, (extract(epoch from (v_end - v_start))/60)::int - v_slot, v_slot) n
  ),
  cand as ( select dd, tt, (dd + tt) as slot_ts from days cross join times ),
  busy as ( select busy_date, start_time, end_time from public.interview_busy_blocks(inv.participant_ids, v_today, v_today + (v_win-1)) ),
  free as (
    select c.slot_ts
    from cand c
    where (c.slot_ts at time zone 'Europe/Berlin') > now() + (v_lead || ' hours')::interval
      and not exists (
        select 1 from busy b
        where b.busy_date = c.dd
          and b.start_time < (c.tt + (v_slot || ' minutes')::interval)::time
          and b.end_time   > c.tt
      )
    order by c.slot_ts
  )
  select coalesce(jsonb_agg(to_char(slot_ts,'YYYY-MM-DD"T"HH24:MI')), '[]'::jsonb) into slots from free;

  return jsonb_build_object('status','open','applicant_name',v_name,'forms',to_jsonb(inv.forms),
                            'expires_at',to_char(inv.expires_at,'YYYY-MM-DD"T"HH24:MI'),'slots',slots);
end $$;

-- ── Slot bestaetigen (oeffentlich, per Token) ─────────────────────────────────
create or replace function public.confirm_interview_slot(p_token text, p_slot text, p_form text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  inv public.interview_invites%rowtype;
  v_name text; cfg jsonb; v_start time; v_end time; v_slot int; v_win int; v_lead int; v_today date;
  s_ts timestamp; s_date date; s_time time; ev_id uuid;
begin
  select * into inv from public.interview_invites where token = p_token;
  if not found then return jsonb_build_object('status','notfound'); end if;
  if inv.status = 'booked' then return jsonb_build_object('status','already_booked'); end if;
  if inv.status <> 'open' or inv.expires_at < now() then return jsonb_build_object('status','expired'); end if;
  if p_form is null or not (p_form = any(inv.forms)) then return jsonb_build_object('status','invalid_form'); end if;

  s_ts := p_slot::timestamp; s_date := s_ts::date; s_time := s_ts::time;
  select value into cfg from public.app_config where key = 'jsr_interview_hours_v1';
  v_start := coalesce((cfg->>'start')::time, time '09:00');
  v_end   := coalesce((cfg->>'end')::time,   time '18:00');
  v_slot  := coalesce((cfg->>'slot_min')::int, 30);
  v_win   := coalesce((cfg->>'window_days')::int, 10);
  v_lead  := coalesce((cfg->>'lead_hours')::int, 1);
  v_today := (now() at time zone 'Europe/Berlin')::date;

  -- Rahmen pruefen: Werktag, im Fenster, in der Buerozeit, nicht in der Vergangenheit.
  if extract(isodow from s_date) not between 1 and 5
     or s_date < v_today or s_date > v_today + (v_win-1)
     or s_time < v_start or (s_time + (v_slot||' minutes')::interval)::time > v_end
     or (s_ts at time zone 'Europe/Berlin') <= now() + (v_lead || ' hours')::interval then
    return jsonb_build_object('status','invalid_slot');
  end if;

  -- Kollisionsschutz: pro Slot-Zeit serialisieren, dann Belegung ATOMAR erneut pruefen.
  perform pg_advisory_xact_lock(hashtext('interview_slot'), hashtext(p_slot));
  if exists (
    select 1 from public.interview_busy_blocks(inv.participant_ids, s_date, s_date) b
    where b.start_time < (s_time + (v_slot||' minutes')::interval)::time and b.end_time > s_time
  ) then
    return jsonb_build_object('status','taken');   -- inzwischen belegt -> Frontend laedt Slots neu
  end if;

  select nullif(trim(coalesce(first_name,'')||' '||coalesce(last_name,'')),'') into v_name from public.cvs where id = inv.cv_id;

  insert into public.calendar_events(title, description, kind, start_date, start_time, end_time, recurrence,
                                     participants, created_by, created_by_name, important)
  values ('Vorstellungsgespraech mit ' || coalesce(v_name,'Bewerber'),
          'Form: ' || case p_form when 'phone' then 'Telefon' when 'teams' then 'Teams' when 'office' then 'Persoenlich im Buero' else p_form end,
          'manual', s_date, s_time, (s_time + (v_slot||' minutes')::interval)::time, 'none',
          inv.participant_ids, inv.created_by, 'Terminvereinbarung', false)
  returning id into ev_id;

  update public.interview_invites
     set status='booked', booked_slot = s_ts, booked_form = p_form, calendar_event_ids = array[ev_id]
   where id = inv.id;

  -- CV-Phase auf 'invited' (nur aus fruehen Phasen, keine Ruecksetzung aus interview/selection/contract).
  update public.cvs set status='invited', status_changed_at = now()
   where id = inv.cv_id and status in ('cv_inbound','cv_accepted','cv_confirmed','invited');

  return jsonb_build_object('status','confirmed','slot',to_char(s_ts,'YYYY-MM-DD"T"HH24:MI'),'form',p_form);
end $$;

grant execute on function public.create_interview_invite(uuid, uuid[], text[]) to authenticated;
grant execute on function public.get_interview_slots(text)                     to anon, authenticated;
grant execute on function public.confirm_interview_slot(text, text, text)      to anon, authenticated;

commit;
