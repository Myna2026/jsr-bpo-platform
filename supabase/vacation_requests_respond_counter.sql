-- ============================================================================
-- Schnitt 2 / Teil A — respond_counter(request_id, accept)
-- MA beantwortet einen HR-Gegenvorschlag (status='counter').
-- SECURITY DEFINER: schreibt die Absence serverseitig, damit der MA KEINE breite
-- UPDATE-Policy auf vacation_requests/employees braucht. Alle Guards IM RPC.
--
-- Erwartete counter_proposal-Form (setzt HR in Teil B):
--   { "from": "YYYY-MM-DD", "to": "YYYY-MM-DD" }
-- ============================================================================

create or replace function public.respond_counter(p_request_id uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row   public.vacation_requests%rowtype;
  v_me    uuid;
  v_from  date;
  v_to    date;
  v_days  integer;
begin
  v_me := public.get_my_employee_id();

  select * into v_row from public.vacation_requests where id = p_request_id;
  if not found then
    raise exception 'Antrag nicht gefunden';
  end if;

  -- Guard 1: nur der Mitarbeiter, dem der Antrag gehört
  if v_me is null or v_row.employee_id <> v_me then
    raise exception 'Kein Zugriff auf diesen Antrag';
  end if;

  -- Guard 2: nur aus status='counter' heraus (kein Doppel-Annehmen, kein
  --          Umbiegen von pending/approved/rejected)
  if v_row.status <> 'counter' then
    raise exception 'Antrag ist nicht im Status counter (aktuell: %)', v_row.status;
  end if;

  if p_accept then
    -- Gegenvorschlags-Daten; Fallback auf die ursprünglichen Antragsdaten
    v_from := coalesce((v_row.counter_proposal->>'from')::date, v_row.from_date);
    v_to   := coalesce((v_row.counter_proposal->>'to')::date,   v_row.to_date);

    -- Werktage (Mo–Fr) im Zeitraum — serverseitig, nicht dem Client vertrauen
    select count(*)::int into v_days
      from generate_series(v_from, v_to, interval '1 day') d
     where extract(dow from d) not in (0, 6);

    -- Absence an den Mitarbeiter schreiben (SECURITY DEFINER umgeht RLS).
    -- Keys wie das Frontend: start/end (Matcher/Workforce) + from/to (Kompat),
    -- type/days/paid; paid = (type <> 'unpaid').
    update public.employees
       set absences = coalesce(absences, '[]'::jsonb) || jsonb_build_object(
             'type',         v_row.type,
             'start',        to_char(v_from, 'YYYY-MM-DD'),
             'end',          to_char(v_to,   'YYYY-MM-DD'),
             'from',         to_char(v_from, 'YYYY-MM-DD'),
             'to',           to_char(v_to,   'YYYY-MM-DD'),
             'days',         v_days,
             'paid',         (v_row.type <> 'unpaid'),
             'approved',     true,
             'approved_by',  'MA (counter akzeptiert)',
             'from_request', p_request_id
           )
     where id = v_row.employee_id;

    -- Antrag auf approved + den vereinbarten Zeitraum festschreiben
    update public.vacation_requests
       set status = 'approved', from_date = v_from, to_date = v_to, days = v_days
     where id = p_request_id;
  else
    -- Ablehnen des Gegenvorschlags: nur Status, keine Absence
    update public.vacation_requests
       set status = 'rejected'
     where id = p_request_id;
  end if;
end;
$$;

revoke all    on function public.respond_counter(uuid, boolean) from public;
grant execute on function public.respond_counter(uuid, boolean) to authenticated;


-- ---- Verifikation (Ausgabe posten) -----------------------------------------
-- 1) RPC existiert + SECURITY DEFINER?
select proname, prosecdef, pg_get_function_identity_arguments(oid) as args
  from pg_proc where proname = 'respond_counter';

-- 2) Aktuelle Policies auf vacation_requests (MA hat KEIN update):
select policyname, cmd from pg_policies
 where schemaname = 'public' and tablename = 'vacation_requests'
 order by cmd, policyname;
