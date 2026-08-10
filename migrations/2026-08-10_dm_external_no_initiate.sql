-- =============================================================================
-- Externe Manager bekommen KEINEN Direktkanal zu Mitarbeitern            2026-08-10
-- =============================================================================
-- Externe Berater (management MIT mgmt_external: Thorsten, Rajner) waren bereits
-- als ZIEL unerreichbar (nicht in chat_universal_contacts, kein Projekt). Offen war
-- die Gegenrichtung: über is_admin() (sie tragen die Rolle management) konnten sie
-- SELBST jeden anschreiben. Sie brauchen keinen Direktkanal zu Mitarbeitern — was
-- sie brauchen, läuft über internes Management.
--
-- Fix: In dm_can_chat ganz vorne prüfen, ob der AUFRUFER ein externer Manager ist.
-- Wenn ja → false (kann keinen Thread anlegen). Greift nur, wenn der externe Manager
-- selbst initiiert; internes Management (Shkurte, Betreiber) bleibt is_admin() und
-- kann Thorsten/Rajner weiterhin anschreiben (der gewünschte Kanal "über Shkurte").
-- Idempotent. Im Supabase SQL-Editor ausführen.
-- =============================================================================

create or replace function public.dm_can_chat(p_other uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare me uuid; me_proj text; ot_proj text;
begin
  me := public.get_my_employee_id();
  if me is null or p_other is null or me = p_other then return false; end if;
  -- Aufrufer ist externer Manager → kein Direktkanal, kann selbst niemanden anschreiben.
  if exists (
    select 1 from public.app_users au
    where au.user_id = auth.uid()
      and 'management' = any(au.role_keys)
      and coalesce(au.mgmt_external, false) = true
  ) then return false; end if;
  if public.is_admin() then return true; end if;                     -- internes management/hr
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
-- Als Thorsten/Rajner: select public.dm_can_chat('<beliebige-employee-uuid>');  -- erwartet: false
-- Als Shkurte (intern): select public.dm_can_chat('<thorsten-employee-uuid>');   -- erwartet: true
