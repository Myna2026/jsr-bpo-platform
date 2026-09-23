-- CPO-Tracking Giganetz Retention (User 2026-09-23). Der Agent erfasst seine Vorgänge EINMAL bei uns; daraus
-- entsteht (a) die Zeile für die Google-Tabelle von Giganetz und (b) unser gewichteter Umsatz.
-- Grundsätze aus der Abstimmung:
--   * Abschluss = abgeschlossen ja UND Maßnahme „Angebot angenommen". Nur dann Tarifart + Rabattstufe, sonst
--     ist der Eintrag reine Dokumentation ohne Umsatz.
--   * Casenummer: beliebig oft als Vorgang (Wiedervorlagen), aber nur EINMAL als Abschluss.
--   * Kein Löschen, nur Storno mit Zeitpunkt, Person und Grund — sonst ändern sich Umsätze rückwirkend unsichtbar.
--   * Der CPO wird beim Erfassen eingefroren (cpo_amount + cpo_basis), spätere Änderungen im Kalkulator
--     schreiben die Vergangenheit nicht um.
--   * Der Agent sieht nie einen CPO: die Tabelle ist für anon/authenticated gesperrt, der Erfassungs-Weg läuft
--     ausschließlich über die Edge Function (service role), die CPO-Felder nie zurückgibt.

create table if not exists public.cpo_entries (
  id            uuid primary key default gen_random_uuid(),
  project_id    text not null,
  skill         text not null default 'retention',
  employee_id   uuid not null references public.employees(id) on delete restrict,
  work_date     date not null,
  case_no       text not null,
  status        text not null,          -- Giganetz Spalte D
  closed        boolean not null,        -- Giganetz Spalte E (ja/nein)
  action        text not null,           -- Giganetz Spalte F
  outcome       text,                    -- unsere Tarifart: downgrade | gleich | upgrade
  discount_level smallint,               -- unsere Rabattstufe: 1 | 2
  cpo_amount    numeric(10,2),           -- eingefroren beim Erfassen
  cpo_basis     jsonb,                   -- woher der Betrag kam (Stufe, Konfig-Stand)
  is_close      boolean generated always as (closed and action = 'Angebot angenommen') stored,
  note          text,
  created_at    timestamptz not null default now(),
  created_via   text not null default 'agent',
  cancelled_at  timestamptz,
  cancelled_by  uuid,
  cancelled_by_name text,
  cancel_reason text,
  constraint cpo_entries_case_no_ck  check (case_no ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{1,39}$'),
  constraint cpo_entries_level_ck    check (discount_level is null or discount_level in (1,2)),
  constraint cpo_entries_outcome_ck  check (outcome is null or outcome in ('downgrade','gleich','upgrade')),
  -- Abschluss braucht Tarifart, Rabattstufe und Betrag; alles andere darf sie nicht tragen.
  constraint cpo_entries_close_ck    check (
    (closed and action = 'Angebot angenommen' and outcome is not null and discount_level is not null and cpo_amount is not null)
    or (not (closed and action = 'Angebot angenommen') and outcome is null and discount_level is null and cpo_amount is null))
);
create index if not exists cpo_entries_proj_date_idx on public.cpo_entries(project_id, work_date desc);
create index if not exists cpo_entries_emp_date_idx  on public.cpo_entries(employee_id, work_date desc);
-- Ein abgerechneter Abschluss je Casenummer (Stornos zählen nicht mit).
create unique index if not exists cpo_entries_close_once_idx
  on public.cpo_entries(project_id, upper(case_no)) where is_close and cancelled_at is null;

-- Zugangslink (wie bei der Telefonaktion): ein Token je Projekt/Skill, dauerhaft nutzbar.
create table if not exists public.cpo_links (
  token       text primary key,
  project_id  text not null,
  skill       text not null default 'retention',
  label       text,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
-- Sitzung nach der PIN-Eingabe, damit die PIN nicht bei jedem Schritt erneut über die Leitung geht.
create table if not exists public.cpo_sessions (
  id          uuid primary key default gen_random_uuid(),
  token       text not null references public.cpo_links(token) on delete cascade,
  employee_id uuid not null,
  emp_name    text,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '14 hours'
);
create index if not exists cpo_sessions_exp_idx on public.cpo_sessions(expires_at);

-- Auswahllisten + Blattname-Hinweis an EINER Stelle, ohne Deploy änderbar (Schreibweise muss exakt zu Giganetz passen).
insert into public.app_config(key, value) values ('jsr_cpo_options_v1', jsonb_build_object(
  'status', jsonb_build_array('erreicht','nicht erreicht','kein call nötig','IB CALL'),
  'action', jsonb_build_array('WVL','WVL-VV','Angebot angenommen','Angebot abgelehnt','Angebot versendet/Wiedervorlage','Case geschlossen','Kündigung in K7 erfasst','WR erfasst','Weitergeleitet'),
  'skill_label', 'Retention',
  'close_action', 'Angebot angenommen'
)) on conflict (key) do nothing;

alter table public.cpo_entries  enable row level security;
alter table public.cpo_links     enable row level security;
alter table public.cpo_sessions  enable row level security;
-- Lesen im HR-Portal: Management/HR/Finance sowie die Leitung des Projekts. Kein anon, kein Agent.
drop policy if exists cpo_entries_read on public.cpo_entries;
create policy cpo_entries_read on public.cpo_entries for select to authenticated
  using (exists (
    select 1 from app_users a where a.user_id = auth.uid() and a.active is distinct from false
      and (a.role_keys && array['management','hr','finance']
           or (a.role_keys && array['projektleiter','teamlead'] and exists (
                 select 1 from employees e where e.id = a.employee_id and e.project_id = cpo_entries.project_id)))));
-- Schreiben/Stornieren läuft über SECURITY-DEFINER-Funktionen, nicht direkt.
revoke all on public.cpo_entries, public.cpo_links, public.cpo_sessions from anon, authenticated;
grant select on public.cpo_entries to authenticated;

-- Storno durch die Teamleitung (der Agent storniert über die Edge Function). Prüft die Rolle selbst,
-- damit die Tabelle für authenticated schreibgeschützt bleiben kann.
create or replace function public.cpo_cancel(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_row cpo_entries%rowtype; v_name text; v_ok boolean;
begin
  if v_uid is null then return jsonb_build_object('error','nicht angemeldet'); end if;
  select * into v_row from cpo_entries where id = p_id;
  if not found then return jsonb_build_object('error','Eintrag nicht gefunden'); end if;
  if v_row.cancelled_at is not null then return jsonb_build_object('error','schon storniert'); end if;
  select coalesce(a.full_name, u.email),
         (a.role_keys && array['management','hr','finance']
          or (a.role_keys && array['projektleiter','teamlead'] and exists (
               select 1 from employees e where e.id = a.employee_id and e.project_id = v_row.project_id)))
    into v_name, v_ok
    from app_users a left join auth.users u on u.id = a.user_id where a.user_id = v_uid;
  if not coalesce(v_ok,false) then return jsonb_build_object('error','keine Berechtigung'); end if;
  update cpo_entries set cancelled_at = now(), cancelled_by = v_uid, cancelled_by_name = v_name,
         cancel_reason = coalesce(nullif(btrim(p_reason),''),'von der Teamleitung storniert')
   where id = p_id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.cpo_cancel(uuid,text) from public, anon;
grant execute on function public.cpo_cancel(uuid,text) to authenticated;

-- Zugangslink für die Agenten (Deutsche GigaNetz, Retention).
insert into public.cpo_links(token, project_id, skill, label)
values ('gn-retention-2026','proj_gn_e5f6a7b8','retention','Deutsche GigaNetz · Retention')
on conflict (token) do update set active = true;
