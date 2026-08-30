-- Rechte Schnitt 6, Scheibe 2: Kennzahlen-RLS auf das Modell (perm_*). Bereich 'kpi'.
-- Tabellen kpi_entries + kpi_project_entries. weekly_hours BEWUSST NICHT (andere, engere Reichweite ohne
-- hr/finance → Taxonomie-Frage, zurückgestellt). forecast_actuals gehört zur Wirtschaftlichkeit (Bereich 6).
--
-- ENTSCHIEDEN (User 2026-08-30): Leads von global auf eigenes Projekt verengen (fachlich richtig, deckt sich mit
-- [[projektleiter-project-access]]); dass mitarbeiter alle Projekt-KPIs global lesen konnte, war ein FEHLER →
-- Korrektur (auf 0). Nicht-Leads unverändert. Skill wie bei Schichten bewusst NULL (kein Skill-Filter in der Basis).
-- Verifiziert (IST->model): mgmt/hr 446/53 unverändert; mitarbeiter kpe 53->0; projektleiter 446->347, 53->51;
-- teamlead 446->99, 53->2.
--
-- FINANCE-Seed kpi read->edit: IST erlaubt Finance KPI-Schreiben (kpi_entries/kpi_project HR-write = mgmt/hr/finance),
-- der Seed stand auf read (unter-granted). Reproduktion, 0 aktive Finance-Nutzer.

begin;

update public.role_permissions set mode='edit' where role_key='finance' and area_key='kpi';

-- ── kpi_entries (emp_id-basiert; Projekt = Projekt des Mitarbeiters; self = eigene Zeilen fürs MA-Portal) ──
drop policy if exists "kpi_entries HR write" on public.kpi_entries;
drop policy if exists "kpi_entries_lead_write" on public.kpi_entries;
drop policy if exists "kpi_entries read internal" on public.kpi_entries;
drop policy if exists "kpi_entries self read" on public.kpi_entries;

create policy ke_perm_select on public.kpi_entries for select to authenticated
using ( emp_id = public.perm_caller_emp_id()
        or ( public.perm_mode(auth.uid(),'kpi') <> 'none'
             and public.perm_proj_ok(auth.uid(),'kpi',
                  (select e.project_id from public.employees e where e.id = kpi_entries.emp_id), null) ) );

create policy ke_perm_insert on public.kpi_entries for insert to authenticated
with check ( public.perm_mode(auth.uid(),'kpi') = 'edit'
             and public.perm_proj_ok(auth.uid(),'kpi',
                  (select e.project_id from public.employees e where e.id = kpi_entries.emp_id), null) );

create policy ke_perm_update on public.kpi_entries for update to authenticated
using ( public.perm_mode(auth.uid(),'kpi') = 'edit'
        and public.perm_proj_ok(auth.uid(),'kpi',
             (select e.project_id from public.employees e where e.id = kpi_entries.emp_id), null) )
with check ( public.perm_mode(auth.uid(),'kpi') = 'edit'
             and public.perm_proj_ok(auth.uid(),'kpi',
                  (select e.project_id from public.employees e where e.id = kpi_entries.emp_id), null) );

create policy ke_perm_delete on public.kpi_entries for delete to authenticated
using ( public.perm_mode(auth.uid(),'kpi') = 'edit'
        and public.perm_proj_ok(auth.uid(),'kpi',
             (select e.project_id from public.employees e where e.id = kpi_entries.emp_id), null) );

-- ── kpi_project_entries (project_id-basiert; kein self) ──
drop policy if exists "kpi_project_entries HR write" on public.kpi_project_entries;
drop policy if exists "kpi_project_entries read internal" on public.kpi_project_entries;

create policy kpe_perm_select on public.kpi_project_entries for select to authenticated
using ( public.perm_mode(auth.uid(),'kpi') <> 'none'
        and public.perm_proj_ok(auth.uid(),'kpi', project_id, null) );

create policy kpe_perm_insert on public.kpi_project_entries for insert to authenticated
with check ( public.perm_mode(auth.uid(),'kpi') = 'edit'
             and public.perm_proj_ok(auth.uid(),'kpi', project_id, null) );

create policy kpe_perm_update on public.kpi_project_entries for update to authenticated
using ( public.perm_mode(auth.uid(),'kpi') = 'edit'
        and public.perm_proj_ok(auth.uid(),'kpi', project_id, null) )
with check ( public.perm_mode(auth.uid(),'kpi') = 'edit'
             and public.perm_proj_ok(auth.uid(),'kpi', project_id, null) );

create policy kpe_perm_delete on public.kpi_project_entries for delete to authenticated
using ( public.perm_mode(auth.uid(),'kpi') = 'edit'
        and public.perm_proj_ok(auth.uid(),'kpi', project_id, null) );

commit;

-- ── ROLLBACK (manuell) ──
-- update public.role_permissions set mode='read' where role_key='finance' and area_key='kpi';
-- drop policy if exists ke_perm_select on public.kpi_entries;
-- drop policy if exists ke_perm_insert on public.kpi_entries;
-- drop policy if exists ke_perm_update on public.kpi_entries;
-- drop policy if exists ke_perm_delete on public.kpi_entries;
-- create policy "kpi_entries HR write" on public.kpi_entries for all to authenticated
--   using (exists (select 1 from app_users where user_id=auth.uid() and role_keys && array['management','hr','finance']::text[]))
--   with check (exists (select 1 from app_users where user_id=auth.uid() and role_keys && array['management','hr','finance']::text[]));
-- create policy "kpi_entries_lead_write" on public.kpi_entries for all to authenticated
--   using (is_planner() and is_emp_in_my_project(emp_id)) with check (is_planner() and is_emp_in_my_project(emp_id));
-- create policy "kpi_entries read internal" on public.kpi_entries for select to authenticated
--   using (exists (select 1 from app_users where user_id=auth.uid() and role_keys && array['management','hr','finance','teamlead','projektleiter']::text[]));
-- create policy "kpi_entries self read" on public.kpi_entries for select to authenticated
--   using (emp_id = (select employee_id from app_users where user_id=auth.uid()));
-- drop policy if exists kpe_perm_select on public.kpi_project_entries;
-- drop policy if exists kpe_perm_insert on public.kpi_project_entries;
-- drop policy if exists kpe_perm_update on public.kpi_project_entries;
-- drop policy if exists kpe_perm_delete on public.kpi_project_entries;
-- create policy "kpi_project_entries HR write" on public.kpi_project_entries for all to authenticated
--   using ((exists (select 1 from app_users where user_id=auth.uid() and role_keys && array['management','hr','finance']::text[])) or (is_planner() and project_id=get_my_employee_project_id()))
--   with check ((exists (select 1 from app_users where user_id=auth.uid() and role_keys && array['management','hr','finance']::text[])) or (is_planner() and project_id=get_my_employee_project_id()));
-- create policy "kpi_project_entries read internal" on public.kpi_project_entries for select to authenticated
--   using (exists (select 1 from app_users where user_id=auth.uid() and role_keys && array['management','hr','finance','teamlead','projektleiter','mitarbeiter']::text[]));
