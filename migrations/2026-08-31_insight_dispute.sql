-- Agenten Round 3, Schnitt 2: Widerspruch „Das stimmt nicht". Viertes Wirkungs-Signal neben seen/dismissed/acted:
-- disputed_at + dispute_reason. Fließt damit in dieselbe Wirkungsmessung (die Signale auf agent_insights). RPC
-- prüft user_id=auth.uid() (man widerspricht nur der eigenen Meldung → Scope unkritisch).
alter table public.agent_insights add column if not exists disputed_at timestamptz;
alter table public.agent_insights add column if not exists dispute_reason text;

create or replace function public.insight_dispute(p_id bigint, p_reason text)
returns void language plpgsql security definer set search_path=public as $$
begin
  update public.agent_insights set
    seen_at        = coalesce(seen_at, now()),
    disputed_at    = now(),
    dispute_reason = nullif(trim(p_reason),'')
  where id = p_id and user_id = auth.uid();
end $$;
grant execute on function public.insight_dispute(bigint, text) to authenticated;
