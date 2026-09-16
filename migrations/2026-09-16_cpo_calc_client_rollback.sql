-- Rückbau des Kundenportal-Anbaus für den CPO-Kalkulator (User-Entscheidung 2026-09-16):
-- Der Kalkulator lebt ausschließlich im HR-Portal als Management-Menüpunkt. Alles, was
-- 2026-09-16_cpo_calc_giganetz.sql fürs Kundenportal angelegt hat, kommt wieder weg:
--   1) Management verliert den Kundenportal-Zugang (Vorschau) wieder.
--   2) RPC client_preview_set (Vorschau-Kundenkonto) entfällt.
--   3) Kunden-View cpo_calc_customer_view entfällt (Kunde sieht den Kalkulator nicht).
--   4) Kundenkonto client_giganetz entfällt (hatte keinen Login, keine verknüpften Daten).
-- Bleibt: Tabelle cpo_calc_configs + Management-only-Policy (Speicher des HR-Kalkulators).

update public.roles_definitions
   set portals = array_remove(portals, 'client')
 where role_key = 'management';

-- Falls ein Management-Zugang in der Zwischenzeit ein Vorschau-Konto gewählt hat: zurücksetzen
-- (der Kunden-Scope hängt am client_id; Management braucht keinen).
update public.app_users
   set client_id = null
 where 'management' = any(role_keys) and not ('kunde' = any(role_keys)) and client_id is not null;

drop function if exists public.client_preview_set(text);
drop view if exists public.cpo_calc_customer_view;

delete from public.client_accounts where id = 'client_giganetz';
