-- AI-Kollegen, Schnitt 4: ungefragtes Bemerken. Je Agent eine tägliche Domänen-Prüfung (Cron, einmal am Tag,
-- global gerechnet). Meldet NUR echte Abweichungen (mit Vorperiode/Vortag oder gespeichertem Vortags-Stand).
-- „Schweigen bedeutet etwas": jede Prüfung schreibt agent_checks (zuletzt geprüft), auch ohne Meldung — dann
-- steht in der UI „geprüft, alles in Ordnung" statt Stille.

-- Befunde (dedupe je Tag über okey → ein Befund-Typ/Subjekt nur einmal pro Tag).
create table if not exists public.agent_observations (
  id bigserial primary key,
  agent_key text not null,
  day date not null,
  okey text not null,                       -- z. B. 'clara_inbox_volume'
  severity text not null default 'info',    -- info | warn | high
  title text not null,                      -- der Kollegen-Satz
  metrics jsonb,
  confidence text,                          -- exakt | obergrenze | vermutung
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique(day, okey)
);
create index if not exists idx_agent_obs_day on public.agent_observations(day desc);
alter table public.agent_observations enable row level security;
-- Management + HR sehen alle Befunde; der nutzerbezogene Filter kommt in Schnitt 5 (Einblendungen).
drop policy if exists agent_obs_sel on public.agent_observations;
create policy agent_obs_sel on public.agent_observations for select to authenticated using (public.is_admin());

-- Heartbeat je Agent: wann zuletzt geprüft, wie viele Befunde, + letzter Snapshot (für Delta-Prüfungen ohne Datum).
create table if not exists public.agent_checks (
  agent_key text primary key,
  last_checked_at timestamptz not null default now(),
  last_day date,
  found_count int not null default 0,
  metrics jsonb,                            -- letzter Stand (z. B. lena_scan-Kategorien) für Vergleich beim nächsten Lauf
  updated_at timestamptz not null default now()
);
alter table public.agent_checks enable row level security;
-- „Zuletzt geprüft" darf jeder angemeldete Nutzer sehen (es ist nur ein Zeitstempel, keine Inhalte).
drop policy if exists agent_checks_sel on public.agent_checks;
create policy agent_checks_sel on public.agent_checks for select to authenticated using (true);
