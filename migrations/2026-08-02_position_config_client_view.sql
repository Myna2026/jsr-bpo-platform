-- =============================================================================
-- Kundenportal: Positions-Kategorien für die Organigramm-Farbcodierung lesbar machen.
-- =============================================================================
-- Das Organigramm färbt Mitarbeiter nach Funktion (Projektleiter / Overhead-Position /
-- Agent). Welche Position welcher Kategorie angehört, steht EINMALIG im HR-System in
-- app_config unter 'jsr_overhead_positions_v1' und 'jsr_company_positions_v1'. Keine
-- zweite Liste im Kundenportal.
--
-- app_config ist per RLS nur für interne Rollen lesbar (kein 'kunde'). Statt die ganze
-- Tabelle zu öffnen (dort liegen auch KPI-/Bonus-/Lohn-Configs), exponiert diese
-- security-definer-View NUR die zwei unkritischen Positions-Listen (reine Positionsnamen,
-- keine sensiblen Daten) an alle authentifizierten Nutzer inkl. Kunde.
-- Im Supabase SQL-Editor ausführen.
-- =============================================================================

drop view if exists public.position_config_client_view;

create view public.position_config_client_view
with (security_invoker = false, security_barrier = true)
as
select key, value
from public.app_config
where key in ('jsr_overhead_positions_v1', 'jsr_company_positions_v1');

grant select on public.position_config_client_view to authenticated;
