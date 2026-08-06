-- =============================================================================
-- Universal-Chat-Kontakte: internes Management + HR projektübergreifend    2026-08-06
-- =============================================================================
-- Jeder Mitarbeiter muss internes Management und HR anschreiben können, egal in
-- welchem Projekt. Der Kollegen-View (employees_team_view) ist hart auf das
-- EIGENE Projekt gefiltert → Management/HR ohne Projekt (Shkurte, Deonita) oder
-- aus anderen Projekten tauchen dort nie auf. Deshalb eine eigene Quelle.
--
-- REGEL (verbindlich):
--   erreichbar     = hr  ODER  (management UND NICHT mgmt_external)
--   nicht erreichbar = management MIT mgmt_external (externe Manager: Thorsten, Rajner)
-- Wahrheit ist app_users (role_keys + mgmt_external), nicht employees.position.
--
-- ZWEI Ebenen, wie überall:
--   1) ANZEIGE über eine SPALTENREDUZIERTE security-definer-View: nur Name, Rolle,
--      Foto — KEINE Gehälter/Bank/Verträge/Personaldaten. Jeder Authentifizierte
--      darf sie lesen (das ist gewollt: alle dürfen Management/HR erreichen).
--   2) ZUGRIFFSREGEL serverseitig: dm_can_chat() (Thread-Anlage-RPC) prüft dieselbe
--      Regel — Anzeige allein reicht nicht.
--
-- Idempotent. Im Supabase SQL-Editor ausführen.
-- =============================================================================

-- ── 1) Spaltenreduzierte Kontakt-View (security definer, nur sichere Spalten) ──
drop view if exists public.chat_universal_contacts;
create view public.chat_universal_contacts
with (security_invoker = false, security_barrier = true)
as
select distinct
  e.id,
  e.first_name,
  e.last_name,
  e.position,
  e.photo_url,
  e.extra->>'photo_color' as photo_color,
  au.role_keys
from public.employees e
join public.app_users au on au.employee_id = e.id
where au.active is not false
  and (
        ('hr' = any(au.role_keys))
     or ('management' = any(au.role_keys) and coalesce(au.mgmt_external, false) = false)
      );

grant select on public.chat_universal_contacts to authenticated;

-- ── 2) Server-Enforcement: dm_can_chat auf dieselbe Regel umstellen ──────────
-- Vorher (2026-07-26_team_chat.sql) prüfte der "Gegenüber ist universal"-Zweig
-- employees.position in ('Management','HR'). Das kennt mgmt_external nicht und
-- ließe externe Manager anschreiben. Ersatz: app_users role_keys + mgmt_external.
create or replace function public.dm_can_chat(p_other uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare me uuid; me_proj text; ot_proj text;
begin
  me := public.get_my_employee_id();
  if me is null or p_other is null or me = p_other then return false; end if;
  if public.is_admin() then return true; end if;                     -- ich = management/hr
  -- Gegenüber ist Universal-Kontakt: internes Management (nicht extern) ODER HR.
  if exists (
    select 1 from public.app_users au
    where au.employee_id = p_other
      and au.active is not false
      and ( ('hr' = any(au.role_keys))
         or ('management' = any(au.role_keys) and coalesce(au.mgmt_external, false) = false) )
  ) then return true; end if;
  -- sonst: gleiches Projekt
  select project_id::text into me_proj from public.employees where id = me;
  select project_id::text into ot_proj from public.employees where id = p_other;
  return me_proj is not null and me_proj = ot_proj;
end; $$;

-- ── Prüfen (optional) ────────────────────────────────────────────────────────
-- select first_name, last_name, position, role_keys from public.chat_universal_contacts
--   order by last_name;   -- erwartet: internes Management + HR; KEIN Thorsten/Rajner
