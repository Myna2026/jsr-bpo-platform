-- Persönliche Ansichts-Einstellungen sind KEIN Admin-Recht (Taxonomie-Punkt). app_config ist admin-write
-- (management/hr/finance), darum konnten teamlead/projektleiter/mitarbeiter ihr eigenes Cockpit nicht anordnen.
-- Eigener per-User-Store mit Zeilen-RLS: jeder liest/schreibt nur seine eigenen Zeilen.
create table if not exists public.user_prefs(
  user_id uuid not null,
  key text not null,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key(user_id, key)
);
alter table public.user_prefs enable row level security;
drop policy if exists user_prefs_own on public.user_prefs;
create policy user_prefs_own on public.user_prefs for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update, delete on public.user_prefs to authenticated;

-- Backfill: bisherige Cockpit-Anordnung aus app_config.jsr_cockpit_v2 ({[uid]:{order,hidden}}) in eigene Zeilen.
insert into public.user_prefs(user_id, key, value)
select (kv.key)::uuid, 'cockpit_v2', kv.value
from public.app_config c, lateral jsonb_each(c.value) kv
where c.key='jsr_cockpit_v2'
  and kv.key ~ '^[0-9a-fA-F-]{36}$'
  and exists (select 1 from public.app_users u where u.user_id = (kv.key)::uuid)
on conflict (user_id, key) do nothing;
