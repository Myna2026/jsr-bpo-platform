-- Vorhaben 4 (Agenten sprechen miteinander), Schnitt 1: das Modell. Ein „Handoff" ist eine GEMEINSAME
-- Erkenntnis aus den Befunden MEHRERER Agenten — etwas, das keiner allein zeigt (Clara: Bewerber-Einbruch +
-- Max: fehlende Uploads -> zusammen). contributors verweist auf die zugrunde liegenden agent_observations,
-- damit die Übergabe nachvollziehbar und über den „Warum"-Weg belegbar bleibt.
create table if not exists public.agent_handoffs (
  id           uuid primary key default gen_random_uuid(),
  day          date not null,
  topic        text not null,                 -- dedupe je Tag
  by_agent     text,                          -- wer die Verbindung gezogen hat (z. B. maya) oder 'system'
  contributors jsonb not null default '[]',   -- [{agent, observation_id, fact}]
  insight      text not null,                 -- die gemeinsame Erkenntnis (ein Satz)
  severity     text not null default 'info',  -- info | warn | high
  created_at   timestamptz not null default now(),
  resolved_at  timestamptz,
  unique(day, topic)
);
create index if not exists agent_handoffs_day on public.agent_handoffs(day desc, created_at desc);
alter table public.agent_handoffs enable row level security;
drop policy if exists agent_handoffs_read on public.agent_handoffs;
create policy agent_handoffs_read on public.agent_handoffs for select using (public.is_management());
grant select on public.agent_handoffs to authenticated;
