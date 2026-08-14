-- =============================================================================
-- windsor_marketing: Zugriff management-only (RLS)                           2026-08-14
-- =============================================================================
-- Quelle: Windsor.ai schreibt taeglich 00:00 UTC ueber den Postgres-DIREKTNUTZER
-- (Transaction Pooler), NICHT ueber die Service-Role. Der Postgres-Nutzer ist
-- Owner/Superuser und umgeht RLS -> der Import bleibt unberuehrt. Die App liest die
-- Tabelle nur, und zwar management-only (wie die anderen Marketing-/Steuerungsdaten).
--
-- KEIN "force row level security" (das wuerde RLS auch fuer den Owner erzwingen und
-- den Import gefaehrden). Nur enable + Policy fuer die App-Rolle 'authenticated'.
--
-- PRUEFEN: Wenn der naechste Import (00:00 UTC) nach dieser Aenderung ausbleibt/scheitert,
-- war die Annahme falsch -> dann zusaetzlich eine Insert-Policy fuer den Windsor-Nutzer.
--
-- Additiv/idempotent. Im Supabase SQL-Editor ausfuehren.
-- =============================================================================
alter table public.windsor_marketing enable row level security;

drop policy if exists windsor_marketing_mgmt on public.windsor_marketing;
create policy windsor_marketing_mgmt on public.windsor_marketing
  for select to authenticated
  using (public.is_management());

grant select on public.windsor_marketing to authenticated;

create index if not exists idx_windsor_marketing_scope
  on public.windsor_marketing (datasource, date);
