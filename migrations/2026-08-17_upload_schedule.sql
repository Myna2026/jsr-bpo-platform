-- =============================================================================
-- Upload-Übersicht mit Ampel — Schnitt 1: Schema + Konfiguration
-- =============================================================================
-- Je Projekt + Quelle: ein Rhythmus (cadence) + Fälligkeit (due_weekday/due_day)
-- + Kulanz (grace_days) + Zuständiger (responsible_user, je Quelle; Rückfall auf
-- projektweiten Standard in upload_project_owner). Die Ampel selbst wird LIVE
-- berechnet (Schnitt 2/3), hier wird NICHTS an Status gespeichert.
-- Zugriff: Management alles; wer einem Projekt zugeordnet ist, liest dessen Plan.
-- Schreiben (Konfiguration): nur Management.
-- Idempotent.
-- =============================================================================

create table if not exists public.upload_schedule (
  id uuid primary key default gen_random_uuid(),
  project_id  text not null,
  source_type text not null,
  active      boolean not null default true,
  cadence     text not null default 'weekly_retro'
    check (cadence in ('daily','weekly_retro','weekly_progressive','monthly')),
  due_weekday int check (due_weekday between 1 and 7),   -- weekly: 1=Mo .. 7=So
  due_day     int check (due_day between 1 and 31),      -- monthly: Tag im Monat
  grace_days  int not null default 1 check (grace_days >= 0),
  responsible_user uuid,                                 -- je Quelle; NULL = Rückfall auf Projekt-Standard
  note        text,
  updated_at  timestamptz not null default now(),
  updated_by  uuid,
  unique (project_id, source_type)
);

create table if not exists public.upload_project_owner (
  project_id       text primary key,
  responsible_user uuid,
  updated_at       timestamptz not null default now(),
  updated_by       uuid
);

alter table public.upload_schedule      enable row level security;
alter table public.upload_project_owner enable row level security;

-- upload_schedule
drop policy if exists upload_schedule_sel on public.upload_schedule;
create policy upload_schedule_sel on public.upload_schedule for select to authenticated
  using ( public.is_management() or project_id = public.get_my_employee_project_id() );
drop policy if exists upload_schedule_ins on public.upload_schedule;
create policy upload_schedule_ins on public.upload_schedule for insert to authenticated
  with check ( public.is_management() );
drop policy if exists upload_schedule_upd on public.upload_schedule;
create policy upload_schedule_upd on public.upload_schedule for update to authenticated
  using ( public.is_management() ) with check ( public.is_management() );
drop policy if exists upload_schedule_del on public.upload_schedule;
create policy upload_schedule_del on public.upload_schedule for delete to authenticated
  using ( public.is_management() );

-- upload_project_owner
drop policy if exists upload_owner_sel on public.upload_project_owner;
create policy upload_owner_sel on public.upload_project_owner for select to authenticated
  using ( public.is_management() or project_id = public.get_my_employee_project_id() );
drop policy if exists upload_owner_ins on public.upload_project_owner;
create policy upload_owner_ins on public.upload_project_owner for insert to authenticated
  with check ( public.is_management() );
drop policy if exists upload_owner_upd on public.upload_project_owner;
create policy upload_owner_upd on public.upload_project_owner for update to authenticated
  using ( public.is_management() ) with check ( public.is_management() );
drop policy if exists upload_owner_del on public.upload_project_owner;
create policy upload_owner_del on public.upload_project_owner for delete to authenticated
  using ( public.is_management() );

grant select, insert, update, delete on public.upload_schedule      to authenticated;
grant select, insert, update, delete on public.upload_project_owner to authenticated;
