-- =============================================================================
-- Punkt 1 / Schnitt 4, Verfeinerung: Rückfall nach NEUESTER Wahrheit             2026-09-02
-- =============================================================================
-- Erste Fassung nahm die Tagesebene immer, wenn es sie gibt. Problem: wo ein SPÄTERER Lauf OHNE archivierte Datei
-- eine Woche aktualisiert hat, stammt die Tagesebene aus einer ÄLTEREN Datei und ist veraltet — die View hätte
-- 21 historische Wochenwerte still geändert (bis 32 h).
--
-- Regel jetzt: je MA-Woche gewinnt der Wert aus dem NEUESTEN Import (Original-Importzeit aus data_imports).
--   * Neuester Import hat Tagesebene  → Tages-Aggregat (from_daily=true).
--   * Neuester Import hat KEINE Datei  → Legacy-Wochenwert (from_daily=false = „für den aktuellen Wert fehlt die
--     Tagesebene"). So bleibt kein alter Wert unbemerkt liegen und keiner ändert sich still.
-- Spalten/Typen/RLS unverändert (create or replace, security_invoker bleibt).
-- =============================================================================

create or replace view public.weekly_hours with (security_invoker = true) as
with da as (
  select d.project_id, d.employee_id,
         extract(isoyear from d.work_date)::int as year,
         extract(week    from d.work_date)::int as kw,
         sum(d.hours)::numeric      as hours,
         sum(d.pause_hours)::numeric as pause_hours,
         sum(d.sales_calls)::int    as sales_calls,
         max(d.skill)               as skill,
         (array_agg(d.import_id order by di.created_at desc nulls last))[1] as import_id,
         coalesce(max(di.created_at), timestamptz '1900-01-01') as src_created
  from public.daily_hours d
  left join public.data_imports di on di.id = d.import_id
  group by d.project_id, d.employee_id, extract(isoyear from d.work_date), extract(week from d.work_date)
),
lg as (
  select l.*, coalesce(li.created_at, timestamptz '1900-01-01') as leg_created
  from public.weekly_hours_legacy l
  left join public.data_imports li on li.id = l.import_id
)
-- Tagesebene gewinnt, wenn es keine Legacy-Zeile gibt ODER die Tagesebene mindestens so neu ist wie der Legacy-Lauf.
select
  md5(da.project_id||'|'||da.employee_id::text||'|'||da.kw||'|'||da.year)::uuid as id,
  da.import_id, da.project_id, da.employee_id, da.kw, da.year, da.skill,
  da.hours, da.pause_hours, null::jsonb as raw, da.src_created as created_at, da.sales_calls,
  true as from_daily
from da
left join lg on lg.project_id=da.project_id and lg.employee_id=da.employee_id and lg.kw=da.kw and lg.year=da.year
where lg.employee_id is null or da.src_created >= lg.leg_created
union all
-- Legacy gewinnt (Rückfall), wenn es keine Tagesebene gibt ODER der Legacy-Lauf NEUER ist als die Tagesebene.
select
  lg.id, lg.import_id, lg.project_id, lg.employee_id, lg.kw, lg.year, lg.skill,
  lg.hours, lg.pause_hours, lg.raw, lg.created_at, lg.sales_calls,
  false as from_daily
from lg
left join da on da.project_id=lg.project_id and da.employee_id=lg.employee_id and da.kw=lg.kw and da.year=lg.year
where da.employee_id is null or lg.leg_created > da.src_created;
