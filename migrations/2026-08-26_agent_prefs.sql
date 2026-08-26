-- AI-Kollegen, Schnitt 12: Steuerung je Nutzer. Jeder legt selbst fest, welche Kollegen sich melden dürfen,
-- wie viele Einblendungen pro Tag, ob eskaliert wird, in welchem Zeitfenster, wie direkt der Ton sein darf.
-- Standard je Rolle im Frontend; jede Person kann es ändern. Eigene Zeile, RLS auf sich selbst.
create table if not exists public.agent_prefs (
  user_id uuid primary key,
  settings jsonb not null default '{}'::jsonb,   -- {agents:{clara:true,…}, max_per_day, escalation, work:{start,end}, tone, min_active_days}
  updated_at timestamptz not null default now()
);
alter table public.agent_prefs enable row level security;
drop policy if exists agent_prefs_own on public.agent_prefs;
create policy agent_prefs_own on public.agent_prefs for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
