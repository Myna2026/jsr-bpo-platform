-- AI-Kollegen, Schnitt 10: ein Eingang, sechs Kollegen. Gespräche werden gespeichert (den Leuten gesagt).
create table if not exists public.agent_conversations (
  id bigserial primary key,
  user_id uuid not null,
  agent_key text not null,
  question text not null,
  answer text,
  created_at timestamptz not null default now()
);
create index if not exists idx_agent_conv_user on public.agent_conversations(user_id, created_at desc);
alter table public.agent_conversations enable row level security;
drop policy if exists agent_conv_sel on public.agent_conversations;
create policy agent_conv_sel on public.agent_conversations for select to authenticated using (user_id = auth.uid());
