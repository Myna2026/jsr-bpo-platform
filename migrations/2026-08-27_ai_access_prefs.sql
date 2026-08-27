-- KI-Datenzugriff je Nutzer (Datenabfrage + Anna), Schnitt 1: Speicher + Auflösung.
-- settings jsonb: { projects:'own'|'list'|'all', project_ids:[uuid], direction:'down'|'side',
--                   salaries:'none'|'own'|'all', overhead_mgmt:bool }
-- Hierarchie aus Position+Projekt (kein Organigramm). Team = Projekt+Skill. Vier feste Voll-Zugriffe.

create table if not exists public.ai_access_prefs (
  user_id uuid primary key,
  settings jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.ai_access_prefs enable row level security;
-- Nur Management darf lesen/setzen (Admin-Bereich); Betroffene sehen ihre eigene Einstellung nicht selbst.
drop policy if exists ai_access_prefs_mgmt on public.ai_access_prefs;
create policy ai_access_prefs_mgmt on public.ai_access_prefs for all to authenticated
  using (public.is_management()) with check (public.is_management());

-- Rang aus Position (fein, nicht nur Kategorie): Management > Projektleiter > Teamleiter/QM/Trainer > Supervisor > Agent.
create or replace function public.ai_position_rank(p_pos text) returns int language sql immutable as $$
  select case
    when p_pos in ('Management','Finance','HR','IT') then 100
    when p_pos = 'Projektleiter' then 40
    when p_pos in ('Teamleiter','Trainer','QM','Quality Manager') then 30
    when p_pos = 'Supervisor' then 20
    when p_pos in ('Senior Agent','ASP') then 12
    when p_pos = 'Agent' then 10
    else 15 end;
$$;

-- Feste Voll-Zugriffe (nicht einstellbar): Shkurte, Rajner, Thorsten, Simon.
create or replace function public.ai_is_full(p_uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from auth.users u where u.id = p_uid
      and lower(u.email) = any (array['info@mynaai.de','sh.cikaqi@25hrs.net','r.gore@tiramu.de','tschroeppe@icloud.com'])
  );
$$;

-- Standard je Rolle (Ausgangspunkt, per Person überschreibbar in ai_access_prefs).
create or replace function public.ai_default_prefs(p_uid uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rk text[];
begin
  select coalesce(role_keys,'{}') into rk from public.app_users where user_id = p_uid;
  if rk && array['management','finance'] then
    return '{"projects":"all","project_ids":[],"direction":"side","salaries":"all","overhead_mgmt":true}'::jsonb;
  elsif 'hr' = any(rk) then
    return '{"projects":"all","project_ids":[],"direction":"side","salaries":"none","overhead_mgmt":true}'::jsonb;
  elsif 'projektleiter' = any(rk) then
    return '{"projects":"own","project_ids":[],"direction":"side","salaries":"none","overhead_mgmt":true}'::jsonb;
  elsif 'teamleiter' = any(rk) then
    return '{"projects":"own","project_ids":[],"direction":"down","salaries":"none","overhead_mgmt":false}'::jsonb;
  else
    return '{"projects":"own","project_ids":[],"direction":"down","salaries":"none","overhead_mgmt":false}'::jsonb;
  end if;
end $$;

-- Effektive Einstellung: feste Voll-Zugriffe → alles; sonst gespeicherte Einstellung, sonst Rollen-Standard.
create or replace function public.ai_effective_prefs(p_uid uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s jsonb;
begin
  if p_uid is null then return '{"projects":"none"}'::jsonb; end if;
  if public.ai_is_full(p_uid) then
    return '{"full":true,"projects":"all","project_ids":[],"direction":"side","salaries":"all","overhead_mgmt":true}'::jsonb;
  end if;
  select settings into s from public.ai_access_prefs where user_id = p_uid;
  if s is null or s = '{}'::jsonb then return public.ai_default_prefs(p_uid); end if;
  return public.ai_default_prefs(p_uid) || s;   -- gespeicherte Werte überschreiben Defaults
end $$;

grant execute on function public.ai_effective_prefs(uuid), public.ai_default_prefs(uuid),
  public.ai_is_full(uuid), public.ai_position_rank(text) to authenticated, service_role;
