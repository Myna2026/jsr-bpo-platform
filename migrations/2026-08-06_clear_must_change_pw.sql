-- =============================================================================
-- Fix Login-Schleife: eigenes must_change_pw zurücksetzen dürfen            2026-08-06
-- =============================================================================
-- BEFUND (latent, nicht von heute): app_users hat NUR die Policy
-- app_users_update_admin (using is_admin()). Ein Mitarbeiter (keine Admin-Rolle)
-- trifft beim UPDATE must_change_pw=false → 0 Zeilen; PostgREST meldet KEINEN
-- Fehler (RLS filtert Zeilen, wirft nicht) → das Frontend hält es für Erfolg,
-- ruft gateSession, das Flag steht noch → Pflicht-Passwortwechsel erscheint
-- erneut → Schleife. Bisher wechselten nur Admin-User (is_admin) das Passwort,
-- deshalb fiel es erst mit dem ersten reinen Mitarbeiter-Login (Eva) auf.
--
-- FIX: eine SECURITY-DEFINER-RPC, die AUSSCHLIESSLICH das must_change_pw der
-- EIGENEN Zeile (user_id = auth.uid()) löscht. Bewusst KEINE Self-UPDATE-Policy
-- auf app_users — die wäre spaltenblind und ließe einen Mitarbeiter seine eigenen
-- role_keys/mgmt_external/active umschreiben (Rechte-Eskalation). Die RPC kann nur
-- dieses eine Feld und gibt zurück, ob die eigene Zeile getroffen wurde — das
-- Frontend meldet einen Fehlschlag dann sichtbar, statt in der Schleife zu enden.
-- Idempotent. Im Supabase SQL-Editor ausführen.
-- =============================================================================

create or replace function public.clear_must_change_pw()
returns boolean language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  update public.app_users
     set must_change_pw = false
   where user_id = auth.uid();
  get diagnostics n = row_count;
  return n > 0;                    -- true = eigene Zeile getroffen und gelöscht
end $$;

revoke all on function public.clear_must_change_pw() from public;
grant execute on function public.clear_must_change_pw() to authenticated;

-- ── Prüfen (optional, als der betroffene User) ───────────────────────────────
-- select public.clear_must_change_pw();          -- erwartet: true
-- select must_change_pw from public.app_users where user_id = auth.uid();  -- false
