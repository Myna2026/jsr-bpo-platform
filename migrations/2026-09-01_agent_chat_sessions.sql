-- Agent-Chat-Sitzungen (wie Claude): jede Unterhaltung eine Sitzung. session_id gruppiert Nachrichten; Altbestand
-- je (user, Kollege) in EINE Früher-Sitzung. Löschen eigener Sitzungen erlauben (SELECT-Policy user_id=auth.uid() existiert).
alter table public.agent_conversations add column if not exists session_id uuid;
update public.agent_conversations
  set session_id = md5(coalesce(user_id::text,'anon')||'|'||coalesce(agent_key,''))::uuid
  where session_id is null;
create index if not exists agent_conv_sess_idx on public.agent_conversations(agent_key, user_id, session_id, created_at);

drop policy if exists agent_conv_del on public.agent_conversations;
create policy agent_conv_del on public.agent_conversations for delete using (user_id = auth.uid());
