-- Zurückgestellte Tabellen, Block 3: Forecast-Tabellen aufs Modell.
--   report_forecast → Präsentationen (Bereich 'praesent'): IST = Management + Planer-eigenes-Projekt. Modell EXAKT
--     (mgmt/Leads=106, hr/mitarbeiter=0), kein Deviation. Skill n.a. (praesent hat keine Skill-Achse).
--   forecast_demand → Schichten (Bereich 'shift'): IST = is_planner() GLOBAL. VERENGUNG (User): Leads global →
--     eigenes Projekt (ein Projektleiter braucht den Bedarf SEINES Projekts; 0 Zeilen = richtiger Zeitpunkt).
--     hr behält alles (is_planner global == shift hr=all), finance draußen. Skill=NULL (shift skill-scopt sonst TL).
--   forecast_config → BEWUSST NICHT (User): globale Rechen-Config (kein Projekt, mgmt/hr/finance). shift-Modell
--     würde Leads reinlassen + Finance rauswerfen. Kategorienfehler wie team_view → bleibt auf IST-Policy.
--     Merkposten Taxonomie: es fehlt eine Global-Config-Ebene.

begin;

-- ── report_forecast (project_id; praesent) ──
drop policy if exists report_forecast_mgmt on public.report_forecast;

create policy rf_perm_select on public.report_forecast for select to authenticated
using ( public.perm_mode(auth.uid(),'praesent') <> 'none'
        and public.perm_proj_ok(auth.uid(),'praesent', project_id, null) );
create policy rf_perm_insert on public.report_forecast for insert to authenticated
with check ( public.perm_mode(auth.uid(),'praesent') = 'edit'
             and public.perm_proj_ok(auth.uid(),'praesent', project_id, null) );
create policy rf_perm_update on public.report_forecast for update to authenticated
using ( public.perm_mode(auth.uid(),'praesent') = 'edit'
        and public.perm_proj_ok(auth.uid(),'praesent', project_id, null) )
with check ( public.perm_mode(auth.uid(),'praesent') = 'edit'
             and public.perm_proj_ok(auth.uid(),'praesent', project_id, null) );
create policy rf_perm_delete on public.report_forecast for delete to authenticated
using ( public.perm_mode(auth.uid(),'praesent') = 'edit'
        and public.perm_proj_ok(auth.uid(),'praesent', project_id, null) );

-- ── forecast_demand (project_id; shift; Leads verengt global→eigenes Projekt) ──
drop policy if exists fd_planner_all on public.forecast_demand;

create policy fd_perm_select on public.forecast_demand for select to authenticated
using ( public.perm_mode(auth.uid(),'shift') <> 'none'
        and public.perm_proj_ok(auth.uid(),'shift', project_id, null) );
create policy fd_perm_insert on public.forecast_demand for insert to authenticated
with check ( public.perm_mode(auth.uid(),'shift') = 'edit'
             and public.perm_proj_ok(auth.uid(),'shift', project_id, null) );
create policy fd_perm_update on public.forecast_demand for update to authenticated
using ( public.perm_mode(auth.uid(),'shift') = 'edit'
        and public.perm_proj_ok(auth.uid(),'shift', project_id, null) )
with check ( public.perm_mode(auth.uid(),'shift') = 'edit'
             and public.perm_proj_ok(auth.uid(),'shift', project_id, null) );
create policy fd_perm_delete on public.forecast_demand for delete to authenticated
using ( public.perm_mode(auth.uid(),'shift') = 'edit'
        and public.perm_proj_ok(auth.uid(),'shift', project_id, null) );

commit;

-- ── ROLLBACK (manuell) ──
-- drop policy if exists rf_perm_select on public.report_forecast; drop policy if exists rf_perm_insert on public.report_forecast;
-- drop policy if exists rf_perm_update on public.report_forecast; drop policy if exists rf_perm_delete on public.report_forecast;
-- create policy report_forecast_mgmt on public.report_forecast for all to authenticated
--   using (is_management() or (is_planner() and (project_id = get_my_employee_project_id())))
--   with check (is_management() or (is_planner() and (project_id = get_my_employee_project_id())));
-- drop policy if exists fd_perm_select on public.forecast_demand; drop policy if exists fd_perm_insert on public.forecast_demand;
-- drop policy if exists fd_perm_update on public.forecast_demand; drop policy if exists fd_perm_delete on public.forecast_demand;
-- create policy fd_planner_all on public.forecast_demand for all to authenticated using (is_planner()) with check (is_planner());
