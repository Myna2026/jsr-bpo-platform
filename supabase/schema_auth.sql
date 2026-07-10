-- ============================================================================
-- TIVE 360° — Auth-Schema (schlank, Login + Rollen-Redirect)
-- Einfügen im Supabase SQL Editor (Dashboard → SQL Editor → New query → Run).
-- Idempotent: kann bei Bedarf erneut ausgeführt werden.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1) Referenz-Tabelle: roles_definitions
--    Die 10 Rollen mit deutschem Label + Portal-Zuordnung.
--    Wird per Migration befuellt, ist read-only fuer die App.
-- ----------------------------------------------------------------------------
create table if not exists public.roles_definitions (
  role_key   text primary key,          -- technischer Schluessel, z.B. 'mitarbeiter'
  label      text not null,             -- Anzeige-Label, z.B. 'Mitarbeiter'
  portals    text[] not null,           -- welche Portale diese Rolle oeffnen darf
  sort_order int
);

-- Seed: alle 10 Rollen (idempotent via ON CONFLICT)
insert into public.roles_definitions (role_key, label, portals, sort_order) values
  ('kunde',         'Kunde',         array['client'],                 10),
  ('mitarbeiter',   'Mitarbeiter',   array['mitarbeiter'],            20),
  ('teamlead',      'Teamlead',      array['mitarbeiter','hr'],       30),
  ('qm',            'QM',            array['mitarbeiter','hr'],       40),
  ('trainer',       'Trainer',       array['mitarbeiter','hr'],       50),
  ('asp',           'ASP',           array['mitarbeiter','hr'],       60),
  ('projektleiter', 'Projektleiter', array['mitarbeiter','hr'],       70),
  ('hr',            'HR',            array['mitarbeiter','hr'],       80),
  ('finance',       'Finance',       array['mitarbeiter','hr'],       90),
  ('management',    'Management',    array['mitarbeiter','hr'],      100)
on conflict (role_key) do update
  set label = excluded.label,
      portals = excluded.portals,
      sort_order = excluded.sort_order;


-- ----------------------------------------------------------------------------
-- 2) Haupt-Tabelle: app_users
--    Verknuepft einen Supabase-Auth-User (auth.users) mit Rollen + Stammdaten.
--    Ein User kann MEHRERE Rollen haben (role_keys als TEXT[]).
-- ----------------------------------------------------------------------------
create table if not exists public.app_users (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  role_keys    text[] not null default '{}',   -- z.B. {'management','mitarbeiter'}
  full_name    text,
  staff_number text,                            -- Personalnummer, optional
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);


-- ----------------------------------------------------------------------------
-- 3) Helper: is_admin()
--    SECURITY DEFINER -> laeuft mit Owner-Rechten und umgeht damit RLS.
--    Verhindert die "infinite recursion", die entstuende, wenn eine
--    app_users-Policy direkt wieder app_users abfragt.
--    Liefert true, wenn der eingeloggte User 'management' ODER 'hr' hat.
-- ----------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.app_users
    where user_id = auth.uid()
      and role_keys && array['management','hr']   -- && = Arrays ueberschneiden sich
  );
$$;


-- ----------------------------------------------------------------------------
-- 4) Trigger: automatische app_users-Zeile bei neuem Auth-User
--    Sobald in auth.users ein User entsteht (Dashboard/Signup), wird eine
--    leere app_users-Zeile (role_keys = '{}') angelegt. Rollen fuellt der
--    Admin danach nach. SECURITY DEFINER, damit der Insert RLS umgeht.
-- ----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.app_users (user_id)
  values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ----------------------------------------------------------------------------
-- 5) Trigger: updated_at automatisch pflegen
-- ----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists app_users_set_updated_at on public.app_users;
create trigger app_users_set_updated_at
  before update on public.app_users
  for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- 6) Grants (Supabase-Modell: Tabellenzugriff gewaehren, RLS schraenkt Zeilen ein)
-- ----------------------------------------------------------------------------
grant select on public.roles_definitions to authenticated;
grant select, insert, update on public.app_users to authenticated;


-- ----------------------------------------------------------------------------
-- 7) Row Level Security aktivieren
-- ----------------------------------------------------------------------------
alter table public.roles_definitions enable row level security;
alter table public.app_users        enable row level security;


-- ----------------------------------------------------------------------------
-- 8) Policies: roles_definitions
--    SELECT fuer alle eingeloggten User. Kein WRITE (Referenz-Tabelle).
-- ----------------------------------------------------------------------------
drop policy if exists roles_definitions_select on public.roles_definitions;
create policy roles_definitions_select
  on public.roles_definitions
  for select
  to authenticated
  using (true);


-- ----------------------------------------------------------------------------
-- 9) Policies: app_users
--    SELECT: jeder liest nur seine eigene Zeile.
--    INSERT/UPDATE: nur Admins (management/hr) via is_admin().
--    (DELETE bewusst nicht erlaubt; Loeschung laeuft ueber Auth-User-Loeschung
--     mit ON DELETE CASCADE.)
-- ----------------------------------------------------------------------------
drop policy if exists app_users_select_self on public.app_users;
create policy app_users_select_self
  on public.app_users
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists app_users_insert_admin on public.app_users;
create policy app_users_insert_admin
  on public.app_users
  for insert
  to authenticated
  with check (public.is_admin());

drop policy if exists app_users_update_admin on public.app_users;
create policy app_users_update_admin
  on public.app_users
  for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());


-- ----------------------------------------------------------------------------
-- 9b) Admin-Lesezugriff auf ALLE app_users — AKTIV (live seit Juli 2026)
--     Die self-Policy (auth.uid() = user_id) allein liesse Admins schreiben,
--     aber keine fremden Zeilen LESEN — was fuer die User-Verwaltung
--     (Liste aller User) noetig ist. Diese Policy ergaenzt den Lesezugriff.
--     Mehrere SELECT-Policies werden mit ODER verknuepft.
-- ----------------------------------------------------------------------------
drop policy if exists app_users_select_admin on public.app_users;
create policy app_users_select_admin
  on public.app_users
  for select
  to authenticated
  using (public.is_admin());


-- ============================================================================
-- FERTIG. Danach: Test-User im Dashboard anlegen (siehe Anleitung im Chat).
-- ============================================================================
