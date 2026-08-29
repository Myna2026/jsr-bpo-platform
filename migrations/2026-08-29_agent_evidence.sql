-- Begründungen Schnitt 2: die Werte hinter einer Agenten-Meldung mitspeichern.
-- Bisher landeten die lesbaren facts[{label,current,prior}] nur im LLM-Satz (title); nur die technischen
-- metrics-Keys waren persistiert. Für den „Warum"-Knopf an der Einblendung brauchen wir die lesbaren Fakten
-- DORT, wo die Zielperson sie lesen darf: auf agent_insights (RLS user_id=auth.uid()). Zusätzlich auf
-- agent_observations (Quelle der Wahrheit, für die spätere Agent-zu-Agent-Übergabe). REIN ADDITIV.
alter table public.agent_observations add column if not exists facts jsonb;
alter table public.agent_insights    add column if not exists facts jsonb;
alter table public.agent_insights    add column if not exists confidence text;
