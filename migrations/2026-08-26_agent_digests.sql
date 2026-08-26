-- Agenten-Aktivität in der täglichen Nutzungs-Zusammenfassung: neben den Menschen laufen die Agenten mit
-- ("Clara hat 60 Bewerbungen vorsortiert"). Eine Zeile je Agent/Tag, aus zählbaren Aktionen. Management-only.
-- Aktuell zählbar: Clara (Meta-Import + automatische Mails). Max/Paul/Anna folgen, sobald ihre Aktionen
-- protokolliert werden.
create table if not exists public.agent_digests (
  day        date not null,
  agent_key  text not null,
  name       text,
  summary    text,
  metrics    jsonb,
  created_at timestamptz not null default now(),
  primary key (day, agent_key)
);
alter table public.agent_digests enable row level security;
drop policy if exists agent_digests_sel on public.agent_digests;
create policy agent_digests_sel on public.agent_digests for select to authenticated using (public.is_management());
grant select on public.agent_digests to authenticated;
