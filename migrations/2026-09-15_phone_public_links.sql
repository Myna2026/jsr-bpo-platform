-- =============================================================================
-- Telefonaktion ohne Anmeldung: je Teilnehmer ein Token-Link (wie Bewerber-Links).
-- Öffentliche Seite telefon.html liest ?t=<token>, ruft token-authentifizierte RPCs
-- (SECURITY DEFINER, an anon vergeben). Kein Portal, kein Login — auf dem Handy nutzbar.
-- Sicherheit = 128-Bit-Token (wie cv-enrich/bewerber.html). Ohne gültigen Token: kein Zugriff.
-- Idempotent.
-- =============================================================================

create extension if not exists pgcrypto;

create table if not exists public.call_access (
  token text primary key default encode(gen_random_bytes(16),'hex'),
  campaign_id uuid not null references public.call_campaigns(id) on delete cascade,
  assignee_user_id uuid not null,
  assignee_name text,
  created_at timestamptz not null default now(),
  unique (campaign_id, assignee_user_id)
);
alter table public.call_access enable row level security;   -- kein Policy → nur SECURITY-DEFINER-RPCs kommen ran

-- Token je (Kampagne, Teilnehmer) aus den bereits verteilten Leads erzeugen (nur fehlende).
insert into public.call_access (campaign_id, assignee_user_id, assignee_name)
select distinct l.campaign_id, l.assignee_user_id, l.assignee_name
from public.call_leads l
on conflict (campaign_id, assignee_user_id) do nothing;

-- ── Öffentlich (anon): Leads zu einem Token laden (mit den fürs Telefonieren nötigen CV-Angaben). ──
create or replace function public.phone_public_load(p_token text)
returns table(assignee_name text, lead_id uuid, first_name text, last_name text, phone text,
  language_level text, cc_experience text, cv_date date, status text, reject_reason text,
  followup_date date, appointment_date date)
language sql stable security definer set search_path=public as $$
  select a.assignee_name, l.id, c.first_name, c.last_name, c.phone, c.language_level,
         (c.extra->>'cc_experience'), c.cv_date, l.status, l.reject_reason, l.followup_date, l.appointment_date
  from public.call_access a
  join public.call_leads l on l.campaign_id=a.campaign_id and l.assignee_user_id=a.assignee_user_id
  join public.cvs c on c.id=l.cv_id
  where a.token = p_token
  order by (l.status<>'open'), c.last_name, c.first_name;
$$;

-- ── Öffentlich (anon): Ergebnis erfassen — token-authentifiziert, sonst identische Automatik wie phonecall_log. ──
create or replace function public.phone_public_log(p_token text, p_lead_id uuid, p_result text, p_reason text default null, p_date date default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare a public.call_access; l public.call_leads; c public.cvs; ev uuid;
begin
  select * into a from public.call_access where token = p_token;
  if not found then raise exception 'Ungültiger Link.'; end if;
  select * into l from public.call_leads where id = p_lead_id;
  if not found or l.campaign_id<>a.campaign_id or l.assignee_user_id<>a.assignee_user_id then
    raise exception 'Nicht berechtigt.'; end if;
  select * into c from public.cvs where id = l.cv_id;

  if p_result = 'no_answer' then
    update public.call_leads set status='no_answer', followup_date=coalesce(p_date, current_date+2),
      reject_reason=null, appointment_date=null, updated_by=a.assignee_user_id, updated_at=now() where id=l.id;
    update public.cvs set last_worked_at=now() where id=l.cv_id;
  elsif p_result = 'rejected' then
    if p_reason is null or p_reason not in ('kein_interesse','zu_weit','hat_anderes') then
      raise exception 'Absagegrund erforderlich.'; end if;
    update public.call_leads set status='rejected', reject_reason=p_reason, followup_date=null,
      appointment_date=null, updated_by=a.assignee_user_id, updated_at=now() where id=l.id;
    update public.cvs set status='rejected_by_us', status_changed_at=now(), last_worked_at=now(),
      extra = coalesce(extra,'{}'::jsonb) || jsonb_build_object('reject_reason', p_reason, 'rejected_via','telefonaktion')
      where id=l.cv_id;
  elsif p_result = 'appointment' then
    if p_date is null then raise exception 'Termindatum erforderlich.'; end if;
    insert into public.calendar_events(title, description, kind, auto_key, start_date, created_by, created_by_name)
      values('Büro-Interview: '||coalesce(c.first_name,'')||' '||coalesce(c.last_name,''),
             'Telefonaktion → Einladung ins Büro. Tel: '||coalesce(c.phone,'—')||', Sprache: '||coalesce(c.language_level,'—'),
             'manual', 'callcamp:'||l.id::text, p_date, a.assignee_user_id, a.assignee_name)
      on conflict (auto_key) do update set start_date=excluded.start_date, updated_at=now()
      returning id into ev;
    update public.call_leads set status='appointment', appointment_date=p_date, reject_reason=null,
      followup_date=null, calendar_event_id=ev, updated_by=a.assignee_user_id, updated_at=now() where id=l.id;
    update public.cvs set status='interview', status_changed_at=now(), last_worked_at=now() where id=l.cv_id;
  elsif p_result = 'open' then
    update public.call_leads set status='open', reject_reason=null, followup_date=null, appointment_date=null,
      updated_by=a.assignee_user_id, updated_at=now() where id=l.id;
  else
    raise exception 'Unbekanntes Ergebnis: %', p_result;
  end if;
  return jsonb_build_object('ok', true, 'result', p_result);
end $$;

revoke all on function public.phone_public_load(text) from public;
revoke all on function public.phone_public_log(text, uuid, text, text, date) from public;
grant execute on function public.phone_public_load(text) to anon, authenticated;
grant execute on function public.phone_public_log(text, uuid, text, text, date) to anon, authenticated;

notify pgrst, 'reload schema';
