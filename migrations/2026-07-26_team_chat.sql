-- ============================================================================
-- TIVE 360° — Team-Chat auf Supabase (Neubau, ersetzt localStorage-Prototyp)
-- Einfügen im Supabase SQL Editor. Idempotent (kann erneut ausgeführt werden).
--
-- Ersetzt jsr_dm_threads_v1 / jsr_dm_messages_v1 (per-Device, nie übertragen).
-- Identität = employee_id über die BESTEHENDE get_my_employee_id() (wie vacation_requests).
-- Wer keine employee_id hat (Rajner/Thorsten/namenlose Zugänge), nimmt bewusst nicht teil.
--
-- Regel canChatWith (serverseitig, NICHT nur im Frontend):
--   management/hr universal · sonst gleiches project_id.
-- Read-Receipts als eigene Tabelle dm_reads (einheitlich DM + Gruppe).
-- ============================================================================

create extension if not exists pgcrypto;

-- Voraussetzung (existiert bereits, hier nur zur Erinnerung — NICHT neu anlegen):
--   public.get_my_employee_id()  -> auth.uid() -> employees.id
--   public.is_admin()            -> app_users.role_keys && {management,hr}


-- ----------------------------------------------------------------------------
-- 1) Tabellen
-- ----------------------------------------------------------------------------
create table if not exists public.dm_threads (
  id         uuid primary key default gen_random_uuid(),
  is_group   boolean not null default false,
  name       text,                       -- nur Gruppen
  dm_key     text unique,                -- 1:1: "minId_maxId" (Dedup); Gruppe: null
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.dm_participants (
  thread_id uuid not null references public.dm_threads(id) on delete cascade,
  emp_id    uuid not null,
  my_lang   text not null default 'de',  -- ersetzt thread.lang_prefs[emp].my_lang
  see_lang  text not null default 'de',  -- ersetzt thread.lang_prefs[emp].see_lang
  joined_at timestamptz not null default now(),
  primary key (thread_id, emp_id)
);
create index if not exists idx_dm_part_emp on public.dm_participants(emp_id);

create table if not exists public.dm_messages (
  id            uuid primary key default gen_random_uuid(),
  thread_id     uuid not null references public.dm_threads(id) on delete cascade,
  from_emp_id   uuid not null,
  text_original text not null,
  lang_original text,
  translations  jsonb not null default '{}',   -- KI-Cache {lang:text}
  sent_at       timestamptz not null default now()
);
create index if not exists idx_dm_msg_thread on public.dm_messages(thread_id, sent_at);

create table if not exists public.dm_reads (
  message_id uuid not null references public.dm_messages(id) on delete cascade,
  emp_id     uuid not null,
  read_at    timestamptz not null default now(),
  primary key (message_id, emp_id)
);
create index if not exists idx_dm_reads_emp on public.dm_reads(emp_id);


-- ----------------------------------------------------------------------------
-- 2) Helper: Mitgliedschaft (SECURITY DEFINER -> keine RLS-Rekursion)
-- ----------------------------------------------------------------------------
create or replace function public.dm_is_member(p_thread uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.dm_participants
    where thread_id = p_thread and emp_id = public.get_my_employee_id()
  );
$$;

-- canChatWith — serverseitige Wahrheit. management/hr universal, sonst gleiches Projekt.
create or replace function public.dm_can_chat(p_other uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare me uuid; me_proj text; ot_proj text;
begin
  me := public.get_my_employee_id();
  if me is null or p_other is null or me = p_other then return false; end if;
  if public.is_admin() then return true; end if;                     -- ich = management/hr (app_users)
  if exists (select 1 from public.employees e
             where e.id = p_other and e.position in ('Management','HR'))
    then return true; end if;                                        -- Gegenüber = management/hr
  select project_id::text into me_proj from public.employees where id = me;
  select project_id::text into ot_proj from public.employees where id = p_other;
  return me_proj is not null and me_proj = ot_proj;                  -- gleiches Projekt
end; $$;


-- ----------------------------------------------------------------------------
-- 3) Trigger: neue Nachricht hebt thread.updated_at (statt Client-UPDATE)
-- ----------------------------------------------------------------------------
create or replace function public.dm_touch_thread()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.dm_threads set updated_at = now() where id = new.thread_id;
  return new;
end; $$;
drop trigger if exists dm_messages_touch on public.dm_messages;
create trigger dm_messages_touch after insert on public.dm_messages
  for each row execute function public.dm_touch_thread();


-- ----------------------------------------------------------------------------
-- 4) RLS. Lesen = Mitglied. Thread-/Gruppen-Anlage NUR über die RPCs unten
--    (SECURITY DEFINER, prüfen canChatWith). Kein direkter Client-Insert auf
--    dm_threads/dm_participants.
-- ----------------------------------------------------------------------------
alter table public.dm_threads      enable row level security;
alter table public.dm_participants enable row level security;
alter table public.dm_messages     enable row level security;
alter table public.dm_reads        enable row level security;

drop policy if exists dm_threads_sel on public.dm_threads;
create policy dm_threads_sel on public.dm_threads
  for select to authenticated using (public.dm_is_member(id));

drop policy if exists dm_part_sel on public.dm_participants;
create policy dm_part_sel on public.dm_participants
  for select to authenticated using (public.dm_is_member(thread_id));
-- eigene Sprach-Präferenzen (my_lang/see_lang) ändern
drop policy if exists dm_part_upd_self on public.dm_participants;
create policy dm_part_upd_self on public.dm_participants
  for update to authenticated
  using (emp_id = public.get_my_employee_id())
  with check (emp_id = public.get_my_employee_id());

drop policy if exists dm_msg_sel on public.dm_messages;
create policy dm_msg_sel on public.dm_messages
  for select to authenticated using (public.dm_is_member(thread_id));
-- senden: nur als man selbst UND Mitglied des Threads
drop policy if exists dm_msg_ins on public.dm_messages;
create policy dm_msg_ins on public.dm_messages
  for insert to authenticated
  with check (from_emp_id = public.get_my_employee_id() and public.dm_is_member(thread_id));

-- Lesehäkchen: Thread-Mitglieder sehen sie (Sender sieht 'gelesen'); eintragen nur eigene
drop policy if exists dm_reads_sel on public.dm_reads;
create policy dm_reads_sel on public.dm_reads
  for select to authenticated
  using (public.dm_is_member((select thread_id from public.dm_messages where id = message_id)));
drop policy if exists dm_reads_ins on public.dm_reads;
create policy dm_reads_ins on public.dm_reads
  for insert to authenticated
  with check (emp_id = public.get_my_employee_id()
    and public.dm_is_member((select thread_id from public.dm_messages where id = message_id)));


-- ----------------------------------------------------------------------------
-- 5) RPCs — Thread öffnen / Gruppe anlegen / Gruppe beitreten.
--    Prüfen canChatWith serverseitig und legen Thread + Teilnehmer atomar an.
-- ----------------------------------------------------------------------------
create or replace function public.dm_start_thread(p_other uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid; k text; tid uuid;
begin
  me := public.get_my_employee_id();
  if me is null then raise exception 'keine employee-Identität'; end if;
  if not public.dm_can_chat(p_other) then raise exception 'Chat mit diesem Kontakt nicht erlaubt'; end if;
  k := least(me::text, p_other::text) || '_' || greatest(me::text, p_other::text);
  select id into tid from public.dm_threads where dm_key = k;
  if tid is not null then return tid; end if;
  insert into public.dm_threads(is_group, dm_key, created_by) values (false, k, me) returning id into tid;
  insert into public.dm_participants(thread_id, emp_id) values (tid, me), (tid, p_other)
    on conflict do nothing;
  return tid;
end; $$;

create or replace function public.dm_create_group(p_name text, p_members uuid[])
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid; tid uuid; m uuid;
begin
  me := public.get_my_employee_id();
  if me is null then raise exception 'keine employee-Identität'; end if;
  insert into public.dm_threads(is_group, name, created_by)
    values (true, coalesce(nullif(trim(p_name), ''), 'Gruppe'), me) returning id into tid;
  insert into public.dm_participants(thread_id, emp_id) values (tid, me) on conflict do nothing;
  foreach m in array coalesce(p_members, '{}'::uuid[]) loop
    if m is not null and m <> me and public.dm_can_chat(m) then
      insert into public.dm_participants(thread_id, emp_id) values (tid, m) on conflict do nothing;
    end if;
  end loop;
  return tid;
end; $$;

create or replace function public.dm_join_group(p_thread uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid; ok boolean;
begin
  me := public.get_my_employee_id();
  if me is null then raise exception 'keine employee-Identität'; end if;
  if not exists (select 1 from public.dm_threads where id = p_thread and is_group)
    then raise exception 'kein Gruppen-Thread'; end if;
  -- Beitritt: management/hr universal, sonst muss man mit einem Mitglied chatten dürfen
  ok := public.is_admin() or exists (
    select 1 from public.dm_participants pp
    where pp.thread_id = p_thread and public.dm_can_chat(pp.emp_id));
  if not ok then raise exception 'Beitritt nicht erlaubt'; end if;
  insert into public.dm_participants(thread_id, emp_id) values (p_thread, me) on conflict do nothing;
end; $$;


-- ----------------------------------------------------------------------------
-- 6) Grants. dm_threads: KEIN insert/update für Clients (nur RPC). dm_participants:
--    update erlaubt (Sprach-Präferenzen). Messages/Reads: select+insert.
-- ----------------------------------------------------------------------------
grant select               on public.dm_threads      to authenticated;
grant select, update       on public.dm_participants to authenticated;
grant select, insert       on public.dm_messages     to authenticated;
grant select, insert       on public.dm_reads        to authenticated;

revoke all on function public.dm_is_member(uuid)          from public;
revoke all on function public.dm_can_chat(uuid)           from public;
revoke all on function public.dm_start_thread(uuid)       from public;
revoke all on function public.dm_create_group(text,uuid[]) from public;
revoke all on function public.dm_join_group(uuid)         from public;
grant execute on function public.dm_is_member(uuid)          to authenticated;
grant execute on function public.dm_can_chat(uuid)           to authenticated;
grant execute on function public.dm_start_thread(uuid)       to authenticated;
grant execute on function public.dm_create_group(text,uuid[]) to authenticated;
grant execute on function public.dm_join_group(uuid)         to authenticated;


-- ----------------------------------------------------------------------------
-- 7) Realtime. Tabellen zur supabase_realtime-Publication hinzufügen (idempotent).
--    postgres_changes respektiert die RLS-Policies oben -> jeder Client bekommt
--    nur Inserts aus seinen eigenen Threads.
-- ----------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['dm_messages','dm_reads','dm_threads','dm_participants'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
