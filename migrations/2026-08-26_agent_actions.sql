-- Zählbare Agenten-Aktionen, damit Max/Paul/Anna in Mayas Tages-Zusammenfassung mitlaufen (wie Clara).
-- Geschrieben von den Edge Functions (service role): task-reminders (Max), meeting-notes-ai (Paul),
-- assistant + nlquery (Anna). usage-digest zählt je Agent/Tag. Management-only lesbar.
create table if not exists public.agent_actions (
  id         uuid primary key default gen_random_uuid(),
  agent_key  text not null,                    -- 'max' | 'paul' | 'anna' | 'clara'
  kind       text not null,                    -- 'reminder_slack','reminder_cliq','summary','analysis','polish','assistant','nlquery'
  at         timestamptz not null default now(),
  meta       jsonb
);
create index if not exists idx_agent_actions_key_at on public.agent_actions(agent_key, at desc);
alter table public.agent_actions enable row level security;
drop policy if exists agent_actions_sel on public.agent_actions;
create policy agent_actions_sel on public.agent_actions for select to authenticated using (public.is_management());
grant select on public.agent_actions to authenticated;
-- Insert nur durch die Edge Functions (service role umgeht RLS) — keine authenticated-Insert-Policy.
