-- =============================================================================
-- app_users: Pflicht-Passwortwechsel beim Erstlogin                   2026-07-21
-- =============================================================================
-- Zweck: Ein Admin legt Accounts mit einem Start-Passwort an. Beim ersten Login
-- muss der User ein eigenes Passwort setzen (Portal blockiert, bis erledigt).
--
--   must_change_pw = true  → Zwangs-Dialog beim Login (HR- + Mitarbeiter-Portal)
--   Nach erfolgreichem Wechsel setzt das Frontend das Flag auf false.
--
-- Der handle_new_user()-Trigger setzt das Flag bei JEDEM neu entstehenden
-- Auth-User auf true (Dashboard-Anlage / Signup). Bereits bestehende User
-- behalten den Spalten-Default false (werden nicht rückwirkend erzwungen) —
-- die 5 Manager sind separat zu flaggen (siehe SQL am Ende, auskommentiert).
--
-- Idempotent (add column if not exists; create or replace function). Anzuwenden
-- im Supabase SQL Editor (hier NICHT ausgeführt). Voraussetzung: schema_auth.sql.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1 Spalte
-- -----------------------------------------------------------------------------
alter table public.app_users add column if not exists must_change_pw boolean not null default false;


-- -----------------------------------------------------------------------------
-- §2 Trigger-Funktion: neue Auth-User bekommen must_change_pw = true
--    (Rest unverändert: leere app_users-Zeile, SECURITY DEFINER umgeht RLS.)
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.app_users (user_id, must_change_pw)
  values (new.id, true)
  on conflict (user_id) do nothing;
  return new;
end;
$$;
-- Trigger selbst bleibt bestehen (on_auth_user_created) — kein re-create nötig.


-- =============================================================================
-- §3 Bestandsflaggung (NICHT Teil der Migration — manuell ausführen)
--    Erst prüfen, dann gezielt flaggen. NICHT den eigenen Admin-Account flaggen.
-- =============================================================================
-- (a) Kandidaten anzeigen (die 5 neu angelegten Manager identifizieren):
--     select user_id, full_name, staff_number, role_keys, created_at
--       from public.app_users order by created_at desc limit 12;
-- (b) Gezielt flaggen (Namen/E-Mails der 5 einsetzen):
--     update public.app_users set must_change_pw = true
--      where full_name in ('Name 1','Name 2','Name 3','Name 4','Name 5');
-- =============================================================================
