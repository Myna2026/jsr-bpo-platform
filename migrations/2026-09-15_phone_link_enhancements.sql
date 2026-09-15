-- =============================================================================
-- Telefonaktion, 3 Ergänzungen: (1) Termin mit Uhrzeit (Kalender start_time),
-- (2) Kommentar/Notiz je Anruf bei allen Ergebnissen, (3) Wiedervorlage-Datum frei
-- wählbar (p_date wurde schon unterstützt, jetzt setzt die Seite es aktiv).
-- Idempotent.
-- =============================================================================

alter table public.call_leads add column if not exists appointment_time time;

-- Leads-RPC um note + appointment_time erweitern (Seite zeigt Notiz + Uhrzeit an).
drop function if exists public.phone_link_leads(text, uuid);
create or replace function public.phone_link_leads(p_token text, p_assignee uuid)
returns table(lead_id uuid, first_name text, last_name text, phone text, language_level text,
  cc_experience text, cv_date date, status text, reject_reason text, followup_date date,
  appointment_date date, appointment_time time, note text)
language sql stable security definer set search_path=public as $$
  select l.id, c.first_name, c.last_name, c.phone, c.language_level, (c.extra->>'cc_experience'),
         c.cv_date, l.status, l.reject_reason, l.followup_date, l.appointment_date, l.appointment_time, l.note
  from public.call_campaigns k
  join public.call_leads l on l.campaign_id=k.id and l.assignee_user_id=p_assignee
  join public.cvs c on c.id=l.cv_id
  where k.public_token = p_token and k.active
  order by (l.status<>'open'), c.last_name, c.first_name;
$$;
grant execute on function public.phone_link_leads(text, uuid) to anon, authenticated;

-- Log-RPC: + p_time (Termin-Uhrzeit) + p_note (Kommentar, alle Ergebnisse).
drop function if exists public.phone_link_log(text, uuid, uuid, text, text, date);
create or replace function public.phone_link_log(p_token text, p_assignee uuid, p_lead_id uuid, p_result text,
  p_reason text default null, p_date date default null, p_time text default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare k public.call_campaigns; l public.call_leads; c public.cvs; nm text; ev uuid; t_time time;
begin
  select * into k from public.call_campaigns where public_token = p_token and active;
  if not found then raise exception 'Ungültiger Link.'; end if;
  select * into l from public.call_leads where id = p_lead_id;
  if not found or l.campaign_id<>k.id or l.assignee_user_id<>p_assignee then raise exception 'Nicht berechtigt.'; end if;
  select * into c from public.cvs where id = l.cv_id;
  nm := l.assignee_name;
  t_time := case when p_time is null or btrim(p_time)='' then null else p_time::time end;

  if p_result = 'no_answer' then
    update public.call_leads set status='no_answer', followup_date=coalesce(p_date, current_date+2),
      reject_reason=null, appointment_date=null, appointment_time=null, note=p_note,
      updated_by=p_assignee, updated_at=now() where id=l.id;
    update public.cvs set last_worked_at=now() where id=l.cv_id;
  elsif p_result = 'rejected' then
    if p_reason is null or p_reason not in ('kein_interesse','zu_weit','hat_anderes') then raise exception 'Absagegrund erforderlich.'; end if;
    update public.call_leads set status='rejected', reject_reason=p_reason, followup_date=null,
      appointment_date=null, appointment_time=null, note=p_note, updated_by=p_assignee, updated_at=now() where id=l.id;
    update public.cvs set status='rejected_by_us', status_changed_at=now(), last_worked_at=now(),
      extra = coalesce(extra,'{}'::jsonb) || jsonb_build_object('reject_reason', p_reason, 'rejected_via','telefonaktion',
              'reject_note', coalesce(p_note,'')) where id=l.cv_id;
  elsif p_result = 'appointment' then
    if p_date is null then raise exception 'Termindatum erforderlich.'; end if;
    insert into public.calendar_events(title, description, kind, auto_key, start_date, start_time, created_by, created_by_name)
      values('Büro-Interview: '||coalesce(c.first_name,'')||' '||coalesce(c.last_name,''),
             'Telefonaktion → Einladung ins Büro. Tel: '||coalesce(c.phone,'—')||', Sprache: '||coalesce(c.language_level,'—')
               ||case when coalesce(p_note,'')<>'' then E'\nNotiz: '||p_note else '' end,
             'manual', 'callcamp:'||l.id::text, p_date, t_time, p_assignee, nm)
      on conflict (auto_key) do update set start_date=excluded.start_date, start_time=excluded.start_time,
        description=excluded.description, updated_at=now() returning id into ev;
    update public.call_leads set status='appointment', appointment_date=p_date, appointment_time=t_time,
      reject_reason=null, followup_date=null, calendar_event_id=ev, note=p_note, updated_by=p_assignee, updated_at=now() where id=l.id;
    update public.cvs set status='interview', status_changed_at=now(), last_worked_at=now() where id=l.cv_id;
  elsif p_result = 'open' then
    update public.call_leads set status='open', reject_reason=null, followup_date=null, appointment_date=null,
      appointment_time=null, note=null, updated_by=p_assignee, updated_at=now() where id=l.id;
  else
    raise exception 'Unbekanntes Ergebnis: %', p_result;
  end if;
  return jsonb_build_object('ok', true, 'result', p_result);
end $$;
grant execute on function public.phone_link_log(text, uuid, uuid, text, text, date, text, text) to anon, authenticated;

notify pgrst, 'reload schema';
