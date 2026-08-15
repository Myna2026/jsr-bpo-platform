-- =============================================================================
-- Booking-Import (HolidayCheck Sales) - Schnitt 1: Datenmodell        2026-08-15
-- =============================================================================
-- (1) Herkunft je Wert: source ('import' | 'manual') auf kpi_entries UND
--     kpi_project_entries. NULL = Altbestand/unbekannt. Import setzt 'import',
--     eine Handaenderung setzt 'manual' (Schnitt 5 zeigt es an).
-- (2) kpi_config bekommt eine Ebene: level ('agent' | 'team'). Reine Team-KPIs
--     duerfen NICHT je Agent im Performance-Tab erscheinen (Schnitt 5 filtert).
-- (3) Fehlende KPIs anlegen (idempotent), Scoping (project_id/skill) von den
--     ECHTEN vorhandenen KPIs GEKLONT: AHT (kpi_1784715166903) fuer Agent,
--     CR (kpi_1784709865565) fuer Team.
--
-- Bereits vorhanden (werden NICHT angelegt, sondern per Id genutzt):
--   AHT  = kpi_1784715166903     CR   = kpi_1784709865565
--   CSAT = kpi_1784715642800     QM   = kpi_1784715867714
--   ACW  = kpi_1784715510384 (Einheit min)
-- Team-Conversion = dieselbe CR-Zeile (bleibt agent-sichtbar, level bleibt 'agent').
-- Neu angelegt: Agent "Sales Calls" + Team "Buchungen" + Team "Sales Calls".
-- Buchungen offen/OSL je Agent bleiben Input-Ids (kpi_hc_open_bookings/kpi_hc_osl),
-- keine eigene KPI-Zeile.
--
-- Additiv & idempotent (mehrfach ausfuehrbar). Im Supabase SQL-Editor ausfuehren.
-- =============================================================================

alter table public.kpi_entries         add column if not exists source text;
alter table public.kpi_project_entries add column if not exists source text;
alter table public.kpi_config          add column if not exists level  text not null default 'agent';

do $$
declare
  a_pid text; a_skill text;   -- Agent-Scope (aus AHT)
  t_pid text; t_skill text;   -- Team-Scope  (aus CR)
begin
  select project_id, coalesce(nullif(skill,''),'sales') into a_pid, a_skill
    from public.kpi_config where id='kpi_1784715166903' limit 1;
  if a_skill is null then a_skill := 'sales'; end if;

  select project_id, coalesce(nullif(skill,''),'sales') into t_pid, t_skill
    from public.kpi_config where id='kpi_1784709865565' limit 1;
  if t_skill is null then t_skill := 'sales'; end if;

  -- Agent: Sales Calls (fehlt). level=agent -> im Performance-Tab sichtbar.
  insert into public.kpi_config(id,project_id,skill,name,type,unit,thresholds,level)
    select 'kpi_sales_calls', a_pid, a_skill, 'Sales Calls','number','', '[]'::jsonb,'agent'
    where not exists (select 1 from public.kpi_config where id='kpi_sales_calls');

  -- Team-KPIs (level=team) fuer kpi_project_entries. Team-Conversion nutzt die CR-Zeile
  -- (die bleibt level=agent, Doppel-KPI). Buchungen und Sales Calls sind eigenstaendige
  -- Team-Aggregate (Buchungen = offline+osl kombiniert; Sales Calls = deduplizierte
  -- unique_sales_calls_by_date, NICHT die Summe der Agenten) -> je eigene Team-Zeile.
  insert into public.kpi_config(id,project_id,skill,name,type,unit,thresholds,level)
    select 'kpi_bookings_team', t_pid, t_skill, 'Buchungen','number','', '[]'::jsonb,'team'
    where not exists (select 1 from public.kpi_config where id='kpi_bookings_team');
  insert into public.kpi_config(id,project_id,skill,name,type,unit,thresholds,level)
    select 'kpi_sales_calls_team', t_pid, t_skill, 'Sales Calls','number','', '[]'::jsonb,'team'
    where not exists (select 1 from public.kpi_config where id='kpi_sales_calls_team');

  raise notice 'Schnitt 1 ok. Agent-Scope project_id=% skill=%. Team-Scope project_id=% skill=%.', a_pid, a_skill, t_pid, t_skill;
end $$;
