-- AI-Kollegen, Schnitt 5: Einblendungen mit Budget. Aus den globalen Beobachtungen (Schnitt 4) werden
-- nutzergerichtete Einblendungen. Regeln (im Frontend/RPC): höchstens 2 pro Person und Tag, nur ungesehene,
-- am richtigen Ort (context = View-Keys), im Arbeitszeit-Fenster. Zustand (gesehen/weggeklickt/gehandelt)
-- wird festgehalten — das ist zugleich die Basis für die Selbstmessung (Schnitt 8).

create table if not exists public.agent_insights (
  id bigserial primary key,
  agent_key text not null,
  user_id uuid not null,                    -- Ziel: angemeldeter Nutzer (auth uid = app_users.user_id)
  observation_id bigint references public.agent_observations(id) on delete cascade,
  okey text not null,
  day date not null,
  title text not null,
  severity text not null default 'info',    -- info | warn | high
  context text[],                           -- View-Keys, wo die Einblendung passt (leer/na = überall)
  created_at timestamptz not null default now(),
  seen_at timestamptz,
  dismissed_at timestamptz,
  acted_at timestamptz,
  unique(user_id, day, okey)
);
create index if not exists idx_agent_insights_user on public.agent_insights(user_id, dismissed_at, seen_at);
alter table public.agent_insights enable row level security;
-- Jeder sieht NUR seine eigenen Einblendungen.
drop policy if exists agent_insights_sel on public.agent_insights;
create policy agent_insights_sel on public.agent_insights for select to authenticated using (user_id = auth.uid());

-- Zustandswechsel nur über RPC (security definer, eigene Zeile) — damit die Wirkungs-Daten sauber bleiben.
create or replace function public.insight_mark(p_id bigint, p_state text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.agent_insights set
    seen_at      = coalesce(seen_at, now()),
    dismissed_at = case when p_state='dismissed' then now() else dismissed_at end,
    acted_at     = case when p_state='acted'     then now() else acted_at end
  where id = p_id and user_id = auth.uid();
end $$;
revoke all    on function public.insight_mark(bigint,text) from public;
grant execute on function public.insight_mark(bigint,text) to authenticated;
