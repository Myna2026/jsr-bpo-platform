-- =============================================================================
-- Telefonaktion: EIN gemeinsamer Link für alle. Beim Öffnen wählt man seinen Namen
-- aus der Liste (Auswahl wird im Browser gemerkt, Wechsel möglich). Ersetzt die
-- per-Teilnehmer-Tokens im Verteilweg — ein Link in die Gruppe, fertig.
-- Sicherheit: der Link (128-Bit) autorisiert die ganze Aktion; die Namenswahl scopt
-- auf die eigenen Leads. Interner Gruppen-Link, geringe Sensibilität (Kollegen).
-- Idempotent.
-- =============================================================================

create extension if not exists pgcrypto;

alter table public.call_campaigns add column if not exists public_token text;
update public.call_campaigns set public_token = encode(gen_random_bytes(16),'hex') where public_token is null;
create unique index if not exists uq_call_campaigns_public_token on public.call_campaigns(public_token);

-- ── Teilnehmerliste zum Token (für die Namensauswahl, mit Fortschritt). ──
create or replace function public.phone_link_participants(p_token text)
returns table(assignee_user_id uuid, assignee_name text, total int, open int)
language sql stable security definer set search_path=public as $$
  select l.assignee_user_id, max(l.assignee_name), count(*)::int, count(*) filter (where l.status='open')::int
  from public.call_campaigns k
  join public.call_leads l on l.campaign_id=k.id
  where k.public_token = p_token and k.active
  group by l.assignee_user_id
  order by max(l.assignee_name);
$$;

-- ── Leads eines gewählten Teilnehmers unter dem Kampagnen-Token. ──
create or replace function public.phone_link_leads(p_token text, p_assignee uuid)
returns table(lead_id uuid, first_name text, last_name text, phone text, language_level text,
  cc_experience text, cv_date date, status text, reject_reason text, followup_date date, appointment_date date)
language sql stable security definer set search_path=public as $$
  select l.id, c.first_name, c.last_name, c.phone, c.language_level, (c.extra->>'cc_experience'),
         c.cv_date, l.status, l.reject_reason, l.followup_date, l.appointment_date
  from public.call_campaigns k
  join public.call_leads l on l.campaign_id=k.id and l.assignee_user_id=p_assignee
  join public.cvs c on c.id=l.cv_id
  where k.public_token = p_token and k.active
  order by (l.status<>'open'), c.last_name, c.first_name;
$$;

-- ── Ergebnis erfassen: Token→Kampagne, Lead muss zu (Kampagne, gewählter Teilnehmer) gehören. ──
create or replace function public.phone_link_log(p_token text, p_assignee uuid, p_lead_id uuid, p_result text, p_reason text default null, p_date date default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare k public.call_campaigns; l public.call_leads; c public.cvs; nm text; ev uuid;
begin
  select * into k from public.call_campaigns where public_token = p_token and active;
  if not found then raise exception 'Ungültiger Link.'; end if;
  select * into l from public.call_leads where id = p_lead_id;
  if not found or l.campaign_id<>k.id or l.assignee_user_id<>p_assignee then raise exception 'Nicht berechtigt.'; end if;
  select * into c from public.cvs where id = l.cv_id;
  nm := l.assignee_name;

  if p_result = 'no_answer' then
    update public.call_leads set status='no_answer', followup_date=coalesce(p_date, current_date+2),
      reject_reason=null, appointment_date=null, updated_by=p_assignee, updated_at=now() where id=l.id;
    update public.cvs set last_worked_at=now() where id=l.cv_id;
  elsif p_result = 'rejected' then
    if p_reason is null or p_reason not in ('kein_interesse','zu_weit','hat_anderes') then raise exception 'Absagegrund erforderlich.'; end if;
    update public.call_leads set status='rejected', reject_reason=p_reason, followup_date=null,
      appointment_date=null, updated_by=p_assignee, updated_at=now() where id=l.id;
    update public.cvs set status='rejected_by_us', status_changed_at=now(), last_worked_at=now(),
      extra = coalesce(extra,'{}'::jsonb) || jsonb_build_object('reject_reason', p_reason, 'rejected_via','telefonaktion') where id=l.cv_id;
  elsif p_result = 'appointment' then
    if p_date is null then raise exception 'Termindatum erforderlich.'; end if;
    insert into public.calendar_events(title, description, kind, auto_key, start_date, created_by, created_by_name)
      values('Büro-Interview: '||coalesce(c.first_name,'')||' '||coalesce(c.last_name,''),
             'Telefonaktion → Einladung ins Büro. Tel: '||coalesce(c.phone,'—')||', Sprache: '||coalesce(c.language_level,'—'),
             'manual', 'callcamp:'||l.id::text, p_date, p_assignee, nm)
      on conflict (auto_key) do update set start_date=excluded.start_date, updated_at=now() returning id into ev;
    update public.call_leads set status='appointment', appointment_date=p_date, reject_reason=null,
      followup_date=null, calendar_event_id=ev, updated_by=p_assignee, updated_at=now() where id=l.id;
    update public.cvs set status='interview', status_changed_at=now(), last_worked_at=now() where id=l.cv_id;
  elsif p_result = 'open' then
    update public.call_leads set status='open', reject_reason=null, followup_date=null, appointment_date=null,
      updated_by=p_assignee, updated_at=now() where id=l.id;
  else
    raise exception 'Unbekanntes Ergebnis: %', p_result;
  end if;
  return jsonb_build_object('ok', true, 'result', p_result);
end $$;

revoke all on function public.phone_link_participants(text) from public;
revoke all on function public.phone_link_leads(text, uuid) from public;
revoke all on function public.phone_link_log(text, uuid, uuid, text, text, date) from public;
grant execute on function public.phone_link_participants(text) to anon, authenticated;
grant execute on function public.phone_link_leads(text, uuid) to anon, authenticated;
grant execute on function public.phone_link_log(text, uuid, uuid, text, text, date) to anon, authenticated;

notify pgrst, 'reload schema';
