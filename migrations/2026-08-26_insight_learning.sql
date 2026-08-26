-- AI-Kollegen, Schnitt 8: Selbstmessung. Aus dem Zustand je Einblendung (seen/dismissed/acted, seit Schnitt 5)
-- wird je MELDUNGS-TYP die Wirkung berechnet: gehandelt / weggeklickt / ignoriert. Was über ~90% ohne Handlung
-- bleibt (bei genug Fällen), wird „gedämpft" und im Frontend seltener gezeigt (max. 1×/Woche statt täglich).

-- Typ-Schlüssel: okey ohne angehängte UUID (Eskalation 'max_escalation_<uuid>' -> 'max_escalation').
create or replace function public.insight_type_key(p_okey text) returns text
language sql immutable as $$ select regexp_replace(coalesce(p_okey,''), '_[0-9a-f-]{8,}$', ''); $$;

-- Wirkung je Typ über p_days Tage (nur gezeigte Einblendungen zählen). Management/HR.
create or replace function public.insight_learning(p_days int default 14)
returns table(agent_key text, type text, shown int, acted int, dismissed int, ignored int, no_action_rate numeric, muted boolean)
language sql stable security definer set search_path = public as $$
  with base as (
    select ai.agent_key, public.insight_type_key(ai.okey) as type,
      (ai.acted_at is not null) as is_acted,
      (ai.dismissed_at is not null and ai.acted_at is null) as is_dismissed,
      (ai.seen_at is not null and ai.dismissed_at is null and ai.acted_at is null and ai.seen_at < now()-interval '12 hours') as is_ignored
    from public.agent_insights ai
    where ai.seen_at >= now() - (p_days || ' days')::interval
      and (auth.uid() is null or public.is_admin())
  )
  select agent_key, type,
    count(*)::int as shown,
    count(*) filter (where is_acted)::int as acted,
    count(*) filter (where is_dismissed)::int as dismissed,
    count(*) filter (where is_ignored)::int as ignored,
    round((count(*) filter (where is_dismissed or is_ignored))::numeric / greatest(count(*),1), 2) as no_action_rate,
    (count(*) >= 5 and count(*) filter (where is_acted) = 0
      and (count(*) filter (where is_dismissed or is_ignored))::numeric / greatest(count(*),1) >= 0.9) as muted
  from base group by agent_key, type;
$$;
revoke all on function public.insight_learning(int) from public;
grant execute on function public.insight_learning(int) to authenticated;

-- Gedämpfte Typen (nur die Schlüssel) — der Client drosselt sie auf höchstens 1×/Woche.
create or replace function public.insight_muted_types(p_days int default 14) returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(type), '{}') from public.insight_learning(p_days) where muted;
$$;
revoke all on function public.insight_muted_types(int) from public;
grant execute on function public.insight_muted_types(int) to authenticated;
