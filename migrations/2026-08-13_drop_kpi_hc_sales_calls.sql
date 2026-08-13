-- =============================================================================
-- KPI kpi_hc_sales_calls entfernen (redundant)                               2026-08-13
-- =============================================================================
-- Sales Calls kommen jetzt aus dem Rohdaten-Import (weekly_hours.sales_calls),
-- nicht mehr aus dieser KPI. Die Kennzahl wird im Frontend nicht mehr gelesen —
-- eine ungepflegte KPI wuerde spaeter nur verwirren. Erst etwaige Eintraege,
-- dann die Definition loeschen. Idempotent. Im Supabase SQL-Editor ausfuehren.
-- =============================================================================
delete from public.kpi_entries where kpi_id = 'kpi_hc_sales_calls';
delete from public.kpi_config  where id     = 'kpi_hc_sales_calls';
