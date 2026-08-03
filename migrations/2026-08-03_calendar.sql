-- =============================================================================
-- Terminkalender (Schnitt 5 der rollenbezogenen Aufgaben)                2026-08-03
-- =============================================================================
-- Zwei Tabellen: die REGEL und ihre AUSNAHMEN.
--
--   calendar_events    = ein Termin oder eine Wiederholungsregel. Anker ist start_date
--                        (bei 'monthly' der Monatstag, bei weekly/biweekly der Wochentag).
--                        kind='auto' + stabiler auto_key = die vier Pflichttermine
--                        (Rechnungstellung, Rechnungsabgleich, Lohnlauf, Überweisung).
--   calendar_overrides = Ausnahmen je konkretem Vorkommen (occurrence_date):
--                        hidden (Einzeltermin ausgeblendet) UND der EINE Erledigt-Merker
--                        (done/done_by/done_at). KEIN FK-Zwang auf ein reales Vorkommen —
--                        das Vorkommen ergibt sich aus der Regel, der Override hängt am Datum.
--
-- Q4/Doppel-Abhaken: Ein Pflichttermin und die zugehörige (zeitgesteuerte) Tagesaufgabe sind
-- DIESELBE Sache. Der Erledigt-Merker lebt AUSSCHLIESSLICH hier (calendar_overrides), nicht in
-- daily_tasks_done. Die Tagesaufgabe ist eine Projektion desselben Vorkommens → einmal abhaken,
-- an beiden Stellen erledigt.
--
-- Sichtbarkeit je Rolle über visible_roles text[] + RLS (nicht nur Frontend-Filter):
--   Lesen Event:  Admin ODER visible_roles leer (= alle) ODER Überschneidung mit meinen Rollen.
--   Schreiben Event (anlegen/ändern/löschen/ausblenden): nur Admin (Management/HR pflegen den Kalender).
--   Override (Erledigt-Merker): wer den Termin SEHEN darf, darf ihn abhaken — damit Finance (kein
--   is_admin) seine Pflichttermine erledigen kann. Sichtbarkeit steuert den Schreibzugriff.
--
-- Abhängigkeit: is_admin() (management/hr) existiert (schema_auth.sql). app_users(user_id, role_keys).
-- Idempotent. Im Supabase SQL-Editor ausführen.
-- =============================================================================

-- ── Helfer: eigene Rollen + Termin-Sichtbarkeit (security definer, RLS-frei lesbar) ──
create or replace function public.get_my_role_keys()
returns text[] language sql stable security definer set search_path=public as $$
  select coalesce(role_keys, '{}'::text[]) from public.app_users where user_id = auth.uid();
$$;

create or replace function public.calendar_event_visible(ev uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists (
    select 1 from public.calendar_events e
    where e.id = ev
      and ( public.is_admin()
            or e.visible_roles = '{}'::text[]
            or e.visible_roles && public.get_my_role_keys() )
  );
$$;

-- ── Termine / Regeln ─────────────────────────────────────────────────────────
create table if not exists public.calendar_events (
  id              uuid primary key default gen_random_uuid(),
  title           text not null,
  description     text,
  project_id      text,                              -- Projektzuordnung; Farbe kommt aus projects.color (Frontend), nicht hier
  kind            text not null default 'manual',    -- manual|auto
  auto_key        text unique,                       -- nur bei kind='auto' (payroll|transfer|invoice_reconcile|invoice_create); manual = NULL
  start_date      date not null,                     -- Anker: Monatstag (monthly) bzw. Wochentag (weekly/biweekly); Einzeltermin bei 'none'
  start_time      time,
  end_time        time,
  recurrence      text not null default 'none',      -- none|weekly|biweekly|monthly
  until_date      date,                              -- optionales Ende der Wiederholung
  visible_roles   text[] not null default '{}',      -- leer = für alle sichtbar; sonst Schnittmenge mit meinen Rollen
  created_by      uuid references auth.users(id) on delete set null,
  created_by_name text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint calendar_events_kind_chk       check (kind in ('manual','auto')),
  constraint calendar_events_recurrence_chk check (recurrence in ('none','weekly','biweekly','monthly'))
);
create index if not exists idx_calendar_events_start on public.calendar_events (start_date);
create index if not exists idx_calendar_events_proj  on public.calendar_events (project_id);

-- ── Ausnahmen je Vorkommen: ausblenden + EIN Erledigt-Merker ─────────────────
create table if not exists public.calendar_overrides (
  id              uuid primary key default gen_random_uuid(),
  event_id        uuid not null references public.calendar_events(id) on delete cascade,
  occurrence_date date not null,                     -- konkretes Vorkommen der Regel
  hidden          boolean not null default false,    -- Einzeltermin ausgeblendet
  done            boolean not null default false,    -- der EINE Erledigt-Merker (auch Quelle der Tagesaufgaben-Projektion)
  done_by         uuid references auth.users(id) on delete set null,
  done_by_name    text,
  done_at         timestamptz,
  note            text,
  updated_at      timestamptz not null default now(),
  unique (event_id, occurrence_date)
);
create index if not exists idx_calendar_ovr_event on public.calendar_overrides (event_id, occurrence_date);

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.calendar_events    enable row level security;
alter table public.calendar_overrides enable row level security;

-- Events: lesen nach Sichtbarkeit, schreiben nur Admin.
drop policy if exists cal_ev_select on public.calendar_events;
create policy cal_ev_select on public.calendar_events
  for select to authenticated
  using ( public.is_admin()
          or visible_roles = '{}'::text[]
          or visible_roles && public.get_my_role_keys() );

drop policy if exists cal_ev_insert on public.calendar_events;
create policy cal_ev_insert on public.calendar_events
  for insert to authenticated with check ( public.is_admin() );

drop policy if exists cal_ev_update on public.calendar_events;
create policy cal_ev_update on public.calendar_events
  for update to authenticated using ( public.is_admin() ) with check ( public.is_admin() );

drop policy if exists cal_ev_delete on public.calendar_events;
create policy cal_ev_delete on public.calendar_events
  for delete to authenticated using ( public.is_admin() );

-- Overrides: wer den Termin sehen darf, darf ihn abhaken/ausblenden (Finance-Pflichttermine!).
drop policy if exists cal_ovr_select on public.calendar_overrides;
create policy cal_ovr_select on public.calendar_overrides
  for select to authenticated using ( public.calendar_event_visible(event_id) );

drop policy if exists cal_ovr_insert on public.calendar_overrides;
create policy cal_ovr_insert on public.calendar_overrides
  for insert to authenticated with check ( public.calendar_event_visible(event_id) );

drop policy if exists cal_ovr_update on public.calendar_overrides;
create policy cal_ovr_update on public.calendar_overrides
  for update to authenticated using ( public.calendar_event_visible(event_id) ) with check ( public.calendar_event_visible(event_id) );

drop policy if exists cal_ovr_delete on public.calendar_overrides;
create policy cal_ovr_delete on public.calendar_overrides
  for delete to authenticated using ( public.calendar_event_visible(event_id) );

grant select, insert, update, delete on public.calendar_events    to authenticated;
grant select, insert, update, delete on public.calendar_overrides to authenticated;

-- ── Auto-Pflichttermine (monatlich). Anker 2026-01, Monatstag = start_date-Tag. ──
-- Idempotent über auto_key. Sichtbar für Management + Finance. Zeiten frei änderbar im Editor.
insert into public.calendar_events (title, description, project_id, kind, auto_key, start_date, recurrence, visible_roles, created_by_name)
values
  ('Rechnungstellung',  'Rechnungen für den Vormonat erstellen.',           null, 'auto', 'invoice_create',    date '2026-01-01', 'monthly', '{management,finance}', 'System'),
  ('Rechnungsabgleich', 'Ein- und ausgehende Rechnungen abgleichen.',       null, 'auto', 'invoice_reconcile', date '2026-01-03', 'monthly', '{management,finance}', 'System'),
  ('Lohnlauf',          'Gehaltsabrechnung erstellen und Lohnlauf durchführen.', null, 'auto', 'payroll',       date '2026-01-10', 'monthly', '{management,finance}', 'System'),
  ('Überweisung',       'Löhne überweisen (Auszahlung 15. des Folgemonats).', null, 'auto', 'transfer',        date '2026-01-14', 'monthly', '{management,finance}', 'System')
on conflict (auto_key) do nothing;
