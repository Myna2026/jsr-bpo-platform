-- Absence-Format vereinheitlichen: respond_counter schreibt die Absence beim Counter-Accept
-- nur noch im from/to-Format (start/end entfernt). Sonst entstünde beim MA-Counter-Accept
-- sofort wieder eine Absence im Alt-Format, an der neue Auswertungen vorbeilaufen.
--
-- Nur der Absence-INSERT-Block ändert sich (Zeilen 'start'/'end' raus). Guards/Signatur/
-- Grants unverändert. Idempotent via create or replace.

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
  v_exit  date;
begin
  v_me := public.get_my_employee_id();

  select * into v_row from public.vacation_requests where id = p_request_id;
  if not found then
    raise exception 'Antrag nicht gefunden';
  end if;

  if v_me is null or v_row.employee_id <> v_me then
    raise exception 'Kein Zugriff auf diesen Antrag';
  end if;

  if v_row.status <> 'counter' then
    raise exception 'Antrag ist nicht im Status counter (aktuell: %)', v_row.status;
  end if;

  if p_accept then
    v_from := coalesce((v_row.counter_proposal->>'from')::date, v_row.from_date);
    v_to   := coalesce((v_row.counter_proposal->>'to')::date,   v_row.to_date);

    select least(e.termination_date, nullif(e.contract->>'end','')::date)
      into v_exit
      from public.employees e where e.id = v_row.employee_id;
    if v_exit is not null and v_to > v_exit then
      raise exception 'Zeitraum liegt nach dem Austritts-/Vertragsende (%)', v_exit;
    end if;

    select count(*)::int into v_days
      from generate_series(v_from, v_to, interval '1 day') d
     where extract(dow from d) not in (0, 6);

    -- EIN Format: from/to (Einzeltag from===to), days. start/end entfernt (2026-07-26).
    update public.employees
       set absences = coalesce(absences, '[]'::jsonb) || jsonb_build_object(
             'type',         v_row.type,
             'from',         to_char(v_from, 'YYYY-MM-DD'),
             'to',           to_char(v_to,   'YYYY-MM-DD'),
             'days',         v_days,
             'paid',         (v_row.type <> 'unpaid'),
             'approved',     true,
             'approved_by',  'MA (counter akzeptiert)',
             'from_request', p_request_id
           )
     where id = v_row.employee_id;

    update public.vacation_requests
       set status = 'approved', from_date = v_from, to_date = v_to, days = v_days
     where id = p_request_id;
  else
    update public.vacation_requests
       set status = 'rejected'
     where id = p_request_id;
  end if;
end;
$$;

revoke all    on function public.respond_counter(uuid, boolean) from public;
grant execute on function public.respond_counter(uuid, boolean) to authenticated;
