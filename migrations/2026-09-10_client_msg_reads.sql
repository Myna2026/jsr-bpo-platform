-- Ungelesen-Zustand für Kundennachrichten (client_team_messages), analog dm_reads beim Team-Chat.
-- Ein Faden = ein thread_key: '<project_id>|team' (Team-Kanal) oder '<project_id>|emp|<employee_id>' (MA-Faden).
-- Pro Nutzer und Faden ein last_read_at. Ungelesen = Nachricht neuer als last_read_at UND nicht selbst verfasst.
-- user_id default auth.uid() → Frontend upsert schickt nur {thread_key, last_read_at}, RLS erzwingt die eigene Zeile.

create table if not exists public.client_msg_reads (
  user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  thread_key   text not null,
  last_read_at timestamptz not null default now(),
  primary key (user_id, thread_key)
);

alter table public.client_msg_reads enable row level security;
grant select, insert, update on public.client_msg_reads to authenticated;

drop policy if exists cmr_own on public.client_msg_reads;
create policy cmr_own on public.client_msg_reads for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
