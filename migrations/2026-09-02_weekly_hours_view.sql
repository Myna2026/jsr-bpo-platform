-- =============================================================================
-- Rohdaten statt Aggregate, Punkt 1 / Schnitt 4: weekly_hours wird zur VIEW      2026-09-02
-- =============================================================================
-- Die feinste Ebene (daily_hours) ist gefüllt (Live-Dual-Write + Backfill). Jetzt wird die Woche NICHT mehr
-- gespeichert, sondern beim Lesen aus den Tagen gebildet. Alle ~9 bestehenden Leser (Cockpit, Lohnlauf, Auswertung,
-- ai_scoped) bleiben unverändert, weil weekly_hours dieselben Spalten behält.
--
-- WICHTIG (Befund aus dem Backfill): nicht jede historische Woche hat Tagesdaten. Von 170 weekly_hours-Zeilen
-- haben 19 keine Tagesebene (3 Wochen komplett, 16 einzelne MA-Zeilen) — sie stammen aus Läufen ohne archivierte
-- Datei. Die View darf sie NICHT verschwinden lassen. Darum: Tages-Aggregat PLUS Legacy-Rückfall je MA-Woche,
-- und eine Spalte `from_daily`, die zeigt, welche Zeile aus dem Rückfall kommt (dort fehlt die Tagesebene).
--
-- RLS/Sichtbarkeit bleibt exakt: die View ist security_invoker=true, delegiert also an die Policies der Basis-
-- tabellen. daily_hours bekommt dieselbe perm-basierte RLS wie weekly_hours heute (Bereich 'shift', nicht hr,
-- Projekt-Scope). weekly_hours_legacy behält seine Policies (wandern beim Rename mit). agent_ro (bypassrls) liest
-- über ai_scoped weiter, braucht nur das SELECT-Grant auf die Tagesebene.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- §1  daily_hours auf DIESELBE perm-basierte RLS wie weekly_hours heute.
--     (ersetzt die is_management-Policy aus Schnitt 1 — sonst sähen Planer ihre
--     Projektstunden über die security_invoker-View nicht mehr.)
-- -----------------------------------------------------------------------------
drop policy if exists daily_hours_mgmt on public.daily_hours;
create policy dh_perm_select on public.daily_hours for select to authenticated
using ( public.perm_mode(auth.uid(),'shift') <> 'none' and not public.is_hr()
        and public.perm_proj_ok(auth.uid(),'shift', project_id, null) );
create policy dh_perm_insert on public.daily_hours for insert to authenticated
with check ( public.perm_mode(auth.uid(),'shift') = 'edit' and not public.is_hr()
             and public.perm_proj_ok(auth.uid(),'shift', project_id, null) );
create policy dh_perm_update on public.daily_hours for update to authenticated
using ( public.perm_mode(auth.uid(),'shift') = 'edit' and not public.is_hr()
        and public.perm_proj_ok(auth.uid(),'shift', project_id, null) )
with check ( public.perm_mode(auth.uid(),'shift') = 'edit' and not public.is_hr()
             and public.perm_proj_ok(auth.uid(),'shift', project_id, null) );
create policy dh_perm_delete on public.daily_hours for delete to authenticated
using ( public.perm_mode(auth.uid(),'shift') = 'edit' and not public.is_hr()
        and public.perm_proj_ok(auth.uid(),'shift', project_id, null) );

-- agent_ro (bypassrls) liest daily_hours über die ai_scoped-Kette → SELECT-Grant nötig.
grant select on public.daily_hours to agent_ro;

-- -----------------------------------------------------------------------------
-- §2  Bestehende Tabelle umbenennen. Daten, Indizes, Policies (wh_perm_*), Grants,
--     der import_id-FK und die employees-FK wandern mit. Bleibt vollständig als Rückfall erhalten.
-- -----------------------------------------------------------------------------
alter table public.weekly_hours rename to weekly_hours_legacy;

-- -----------------------------------------------------------------------------
-- §3  weekly_hours als VIEW: Tages-Aggregat (from_daily=true) + Legacy-Rückfall je MA-Woche ohne
--     Tagesdeckung (from_daily=false). Spaltenreihenfolge/-typen identisch zur alten Tabelle
--     (Casts halten sales_calls int, hours/pause numeric — sonst bräche ai_scoped beim Replace).
-- -----------------------------------------------------------------------------
create view public.weekly_hours with (security_invoker = true) as
  select
    md5(a.project_id||'|'||a.employee_id::text||'|'||a.kw||'|'||a.year)::uuid as id,
    a.import_id, a.project_id, a.employee_id, a.kw, a.year, a.skill,
    a.hours, a.pause_hours, null::jsonb as raw, a.created_at, a.sales_calls,
    true as from_daily
  from (
    select project_id, employee_id,
           extract(isoyear from work_date)::int as year,
           extract(week    from work_date)::int as kw,
           (array_agg(import_id order by work_date desc nulls last))[1] as import_id,  -- Lauf des jüngsten Tages
           max(skill)             as skill,
           sum(hours)::numeric    as hours,
           sum(pause_hours)::numeric as pause_hours,
           sum(sales_calls)::int  as sales_calls,
           max(created_at)        as created_at
    from public.daily_hours
    group by project_id, employee_id, extract(isoyear from work_date), extract(week from work_date)
  ) a
  union all
  select l.id, l.import_id, l.project_id, l.employee_id, l.kw, l.year, l.skill,
         l.hours, l.pause_hours, l.raw, l.created_at, l.sales_calls,
         false as from_daily
  from public.weekly_hours_legacy l
  where not exists (
    select 1 from public.daily_hours d
    where d.project_id = l.project_id and d.employee_id = l.employee_id
      and extract(isoyear from d.work_date)::int = l.year
      and extract(week    from d.work_date)::int = l.kw
  );

grant select on public.weekly_hours to authenticated, anon, service_role, agent_ro;

-- -----------------------------------------------------------------------------
-- §4  ai_scoped.weekly_hours neu an die VIEW binden (folgte sonst dem Rename zur Legacy-Tabelle).
--     Definition unverändert (perm-Scope über ai_uid), nur explizit auf public.weekly_hours.
-- -----------------------------------------------------------------------------
create or replace view ai_scoped.weekly_hours as
  select id, import_id, project_id, employee_id, kw, year, skill, hours, pause_hours, raw, created_at, sales_calls
  from public.weekly_hours t
  where case
    when employee_id is not null then exists (
      select 1 from public.employees e
      where e.id = t.employee_id and public.perm_emp_row_ok(public.ai_uid(),'kpi', e.id, e.project_id, e.skill, e."position"))
    else public.perm_proj_ok(public.ai_uid(),'kpi', project_id, skill)
  end;

commit;
