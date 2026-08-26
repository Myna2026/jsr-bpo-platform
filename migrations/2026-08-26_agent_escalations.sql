-- AI-Kollegen, Schnitt 7: Eskalation in fünf Stufen bei wiederkehrend offenen Aufgaben (Max' Gebiet, Slack).
-- Eine offene Eskalation je Person und Thema; steigt einmal am Tag, solange offen; löst sich, wenn erledigt.
create table if not exists public.agent_escalations (
  id bigserial primary key,
  user_id uuid not null,
  subject text not null default 'tasks',
  stage int not null default 1,          -- 1 neutral, 2 beiläufig, 3 Frage, 4 Ankündigung, 5 gemeldet
  open_count int,
  opened_on date not null default current_date,
  last_tick date,                        -- letzter Tag, an dem hochgestuft wurde (max. 1×/Tag)
  escalated_at timestamptz,              -- wann an Management gemeldet (Stufe 5)
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index if not exists uq_agent_esc_open on public.agent_escalations(user_id, subject) where resolved_at is null;
create index if not exists idx_agent_esc_user on public.agent_escalations(user_id);
alter table public.agent_escalations enable row level security;
drop policy if exists agent_esc_sel on public.agent_escalations;
create policy agent_esc_sel on public.agent_escalations for select to authenticated using (public.is_admin());
