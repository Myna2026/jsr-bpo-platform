-- =============================================================================
-- Telefonaktion: Kampagne + zugeteilte Leads je Teilnehmer + Ergebnis-Pflege.
-- Ziel: qualifizierte Eingangs-Bewerber anrufen und ins Büro-Interview einladen.
-- Kein Excel: der Bewerber-Status im Trichter, der Kalendertermin und die Pflege
-- laufen an EINER Stelle. Pflege über eine SECURITY-DEFINER-RPC, damit auch
-- Teilnehmer ohne direktes cvs-Schreibrecht (Trainer/QM/Agent) gefahrlos erfassen.
-- Idempotent.
-- =============================================================================

create extension if not exists pgcrypto;

create table if not exists public.call_campaigns (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  active boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.call_leads (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.call_campaigns(id) on delete cascade,
  cv_id uuid not null references public.cvs(id) on delete cascade,
  assignee_user_id uuid not null,          -- app_users.user_id / auth.uid des Teilnehmers
  assignee_name text,                       -- Snapshot fuer Anzeige
  status text not null default 'open' check (status in ('open','no_answer','rejected','appointment')),
  reject_reason text,                       -- kein_interesse | zu_weit | hat_anderes
  followup_date date,                       -- Wiedervorlage (bei no_answer)
  appointment_date date,                    -- Buero-Interview (bei appointment)
  calendar_event_id uuid,                   -- verknuepfter Kalendereintrag
  note text,
  updated_by uuid,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (campaign_id, cv_id)
);
create index if not exists idx_call_leads_assignee on public.call_leads(assignee_user_id, status);
create index if not exists idx_call_leads_campaign on public.call_leads(campaign_id);

alter table public.call_campaigns enable row level security;
alter table public.call_leads     enable row level security;

-- Lesen: eigene Leads ODER Management/HR (fuer Clara/Uebersicht). Kampagnen: alle Angemeldeten lesen.
drop policy if exists call_campaigns_read on public.call_campaigns;
create policy call_campaigns_read on public.call_campaigns for select to authenticated using (true);
drop policy if exists call_leads_read on public.call_leads;
create policy call_leads_read on public.call_leads for select to authenticated
  using (assignee_user_id = auth.uid() or public.is_management() or public.is_hr());
-- Schreiben ausschliesslich ueber die RPC (SECURITY DEFINER); keine direkte INSERT/UPDATE-Policy noetig.

grant select on public.call_campaigns to authenticated;
grant select on public.call_leads to authenticated;

-- ── Meine Leads (mit den fuer den Anruf noetigen CV-Angaben) — bypassed cvs-RLS, aber nur die eigenen. ──
create or replace function public.phonecall_my_leads(p_campaign uuid default null)
returns table(
  lead_id uuid, cv_id uuid, first_name text, last_name text, phone text,
  language_level text, cc_experience text, cv_date date,
  status text, reject_reason text, followup_date date, appointment_date date, note text
)
language sql stable security definer set search_path=public as $$
  select l.id, c.id, c.first_name, c.last_name, c.phone,
         c.language_level, (c.extra->>'cc_experience'), c.cv_date,
         l.status, l.reject_reason, l.followup_date, l.appointment_date, l.note
  from public.call_leads l join public.cvs c on c.id=l.cv_id
  where l.assignee_user_id = auth.uid()
    and (p_campaign is null or l.campaign_id = p_campaign)
  order by (l.status<>'open'), c.last_name, c.first_name;
$$;
grant execute on function public.phonecall_my_leads(uuid) to authenticated;

-- ── Uebersicht je Teilnehmer (Clara/Management). ──
create or replace function public.phonecall_overview(p_campaign uuid)
returns table(assignee_user_id uuid, assignee_name text, total int, open int, no_answer int, rejected int, appointment int, followups_due int)
language sql stable security definer set search_path=public as $$
  select l.assignee_user_id, max(l.assignee_name),
         count(*)::int,
         count(*) filter (where l.status='open')::int,
         count(*) filter (where l.status='no_answer')::int,
         count(*) filter (where l.status='rejected')::int,
         count(*) filter (where l.status='appointment')::int,
         count(*) filter (where l.status='no_answer' and l.followup_date is not null and l.followup_date <= current_date)::int
  from public.call_leads l
  where l.campaign_id = p_campaign and (public.is_management() or public.is_hr())
  group by l.assignee_user_id
  order by max(l.assignee_name);
$$;
grant execute on function public.phonecall_overview(uuid) to authenticated;

-- ── Ergebnis erfassen (der Kern). Verifiziert den Aufrufer, setzt Lead + CV-Status + Kalender + last_worked_at. ──
create or replace function public.phonecall_log(p_lead_id uuid, p_result text, p_reason text default null, p_date date default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare l public.call_leads; c public.cvs; ev uuid; uname text;
begin
  select * into l from public.call_leads where id = p_lead_id;
  if not found then raise exception 'Lead nicht gefunden.'; end if;
  if not (l.assignee_user_id = auth.uid() or public.is_management() or public.is_hr()) then
    raise exception 'Nicht berechtigt (fremder Lead).';
  end if;
  select * into c from public.cvs where id = l.cv_id;
  select full_name into uname from public.app_users where user_id = auth.uid();

  if p_result = 'no_answer' then
    update public.call_leads set status='no_answer', followup_date=coalesce(p_date, current_date+2),
      reject_reason=null, appointment_date=null, note=p_note, updated_by=auth.uid(), updated_at=now() where id=l.id;
    update public.cvs set last_worked_at=now() where id=l.cv_id;   -- bleibt im Eingang, aber "angefasst"

  elsif p_result = 'rejected' then
    if p_reason is null or p_reason not in ('kein_interesse','zu_weit','hat_anderes') then
      raise exception 'Absagegrund erforderlich (kein_interesse|zu_weit|hat_anderes).'; end if;
    update public.call_leads set status='rejected', reject_reason=p_reason, followup_date=null,
      appointment_date=null, note=p_note, updated_by=auth.uid(), updated_at=now() where id=l.id;
    -- CV-Status: Absage durch uns (KEINE Mail hier), Grund in extra festhalten (wertvoll fuer spaeter).
    update public.cvs set status='rejected_by_us', status_changed_at=now(), last_worked_at=now(),
      extra = coalesce(extra,'{}'::jsonb) || jsonb_build_object('reject_reason', p_reason, 'rejected_via','telefonaktion')
      where id=l.cv_id;

  elsif p_result = 'appointment' then
    if p_date is null then raise exception 'Termindatum erforderlich.'; end if;
    -- Kalendereintrag fuers Buero-Interview (idempotent je Lead via auto_key).
    insert into public.calendar_events(title, description, kind, auto_key, start_date, created_by, created_by_name)
      values('Büro-Interview: '||coalesce(c.first_name,'')||' '||coalesce(c.last_name,''),
             'Telefonaktion → Einladung ins Büro. Tel: '||coalesce(c.phone,'—')||', Sprache: '||coalesce(c.language_level,'—'),
             'manual', 'callcamp:'||l.id::text, p_date, auth.uid(), uname)
      on conflict (auto_key) do update set start_date=excluded.start_date, updated_at=now()
      returning id into ev;
    update public.call_leads set status='appointment', appointment_date=p_date, reject_reason=null,
      followup_date=null, calendar_event_id=ev, note=p_note, updated_by=auth.uid(), updated_at=now() where id=l.id;
    -- CV-Status: Interview im Büro (das Ziel der Aktion).
    update public.cvs set status='interview', status_changed_at=now(), last_worked_at=now() where id=l.cv_id;

  elsif p_result = 'open' then   -- zuruecksetzen (Korrektur)
    update public.call_leads set status='open', reject_reason=null, followup_date=null, appointment_date=null,
      note=p_note, updated_by=auth.uid(), updated_at=now() where id=l.id;

  else
    raise exception 'Unbekanntes Ergebnis: %', p_result;
  end if;

  return jsonb_build_object('ok', true, 'result', p_result, 'lead_id', l.id);
end $$;
grant execute on function public.phonecall_log(uuid, text, text, date, text) to authenticated;
-- (calendar_events.auto_key hat bereits einen Unique-Index calendar_events_auto_key_key → ON CONFLICT greift.)

notify pgrst, 'reload schema';
