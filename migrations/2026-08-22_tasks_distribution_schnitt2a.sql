-- Arbeitsverteilung Schnitt 2a: daily_tasks_done auf INSTANZ-Koernung (pro Zustaendigem + Projekt).
-- "Erledigt" ist nicht mehr team-geteilt (frueher global je task_key+date), sondern JE PERSON. So sieht man,
-- wer zustaendig war und wer tatsaechlich erledigt hat, und die Slack-/Cliq-Erinnerung weiss, wen sie erreicht.
-- WICHTIG: gemeinsam mit dem Frontend deployen (Upsert-Conflict-Target aendert sich). Bestehende Zeilen
-- behalten assignee_user/project_id = NULL -> Alt-Haken bleiben gueltig (NULLS NOT DISTINCT).

alter table public.daily_tasks_done add column if not exists assignee_user uuid;
alter table public.daily_tasks_done add column if not exists project_id text;
alter table public.daily_tasks_done add column if not exists id uuid;
update public.daily_tasks_done set id = gen_random_uuid() where id is null;
alter table public.daily_tasks_done alter column id set default gen_random_uuid();
alter table public.daily_tasks_done alter column id set not null;
alter table public.daily_tasks_done drop constraint daily_tasks_done_pkey;
alter table public.daily_tasks_done add constraint daily_tasks_done_pkey primary key (id);
alter table public.daily_tasks_done add constraint daily_tasks_done_instance_uniq
  unique nulls not distinct (task_key, date, assignee_user, project_id);

-- Benachrichtigungs-Kanal je Person (Teil 5 vorbereitet, additiv): Slack ODER Zoho Cliq (via Make) ODER aus.
-- Globaler Standard in app_config 'jsr_notify_channel_default' (Frontend/Dispatcher liest ihn als Fallback).
create table if not exists public.notify_prefs (
  user_id uuid primary key references auth.users(id) on delete cascade,
  channel text not null default 'slack' check (channel in ('slack','cliq','none')),
  updated_at timestamptz not null default now()
);
alter table public.notify_prefs enable row level security;
create policy notify_prefs_sel on public.notify_prefs
  for select to authenticated using (is_planner());
create policy notify_prefs_write on public.notify_prefs
  for all to authenticated using (is_management()) with check (is_management());
grant select, insert, update, delete on public.notify_prefs to authenticated;
