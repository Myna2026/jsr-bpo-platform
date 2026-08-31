-- Agenten Round 3, Schnitt 1: Handlungsangebot aus der Meldung. Die Insight trägt optional eine ANGEBOTENE AKTION
-- aus einem Katalog (kein Freitext): {key, label}. Ausgeführt wird sie erst auf Bestätigung über agent-act, streng
-- innerhalb der Guardrails (nur getemplate; interne Aufforderungen an eigene Leute erlaubt; keine freien Außen-Mails;
-- keine Entscheidungen). Zielmenge wird mit perm() des Bestätigenden geschnitten. Protokoll in agent_action_log.

alter table public.agent_insights add column if not exists action jsonb;   -- {key, label} oder null

create table if not exists public.agent_action_log (
  id uuid primary key default gen_random_uuid(),
  insight_id bigint references public.agent_insights(id) on delete set null,
  action_key text not null,
  actor uuid,                                -- wer bestätigt hat
  target_count int,                          -- wie viele (perm-gescopt) angeschrieben
  detail jsonb,
  created_at timestamptz not null default now()
);
alter table public.agent_action_log enable row level security;
-- Lesen: der Bestätigende sieht seine eigenen Ausführungen; Management alles.
drop policy if exists aal_select on public.agent_action_log;
create policy aal_select on public.agent_action_log for select to authenticated
using ( actor = auth.uid() or public.is_management() );
-- Schreiben nur service_role (agent-act) — keine authenticated-Inserts.
