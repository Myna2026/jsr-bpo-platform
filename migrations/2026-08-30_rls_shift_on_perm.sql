-- Rechte Schnitt 6, Scheibe 1 (Beweislauf): Schichten/Zeit-RLS auf das Modell (perm_*) umstellen.
-- Bereich 'shift'. Tabellen shift_assignments + shift_checkins. Exakte Basis-IST-Parität verifiziert
-- (je Rolle IST-Sicht == Modell-Sicht): management/hr = alle 1155, projektleiter = eigenes Projekt 835,
-- teamlead = eigenes Projekt 320 (OHNE Skill-Filter; MIT Skill fehlten 25 → siehe unten), mitarbeiter = self.
--
-- SKILL BEWUSST NICHT GEFILTERT (perm_proj_ok mit skill=NULL): die Basis-RLS hat Teamleiter NIE skill-scopt,
-- nur die KI (ai_scoped) tut das. Würde die Policy den echten Skill filtern, verlöre ein Teamleiter plötzlich
-- die Schichten anderer Skills im eigenen Projekt = ÄNDERUNG, keine Nachbildung. Der Skill-Ausschnitt für
-- Schichten ist eine bewusste Soll-Erweiterung für später (dann echte Skill-Achse in der Basis-Policy).
--
-- FINANCE-SEED auf Daten-IST: Finance hat bei Schichten KEINEN Back-Office-Zugriff (IST: nicht is_admin,
-- nicht is_planner → nur self). Seed stand auf read/all (das ist der Menü-IST, Schnitt 3), was einem
-- Finance-Nutzer über die Modell-Policy ALLE Schichten gäbe. 0 aktive Finance-Nutzer → kein Live-Effekt,
-- aber korrekt für die Zukunft. visible bleibt unberührt (Menü unverändert).

begin;

update public.role_permissions set mode='none' where role_key='finance' and area_key='shift';

-- ── shift_assignments ──
drop policy if exists sa_planner_all on public.shift_assignments;
drop policy if exists sa_self_select on public.shift_assignments;

create policy sa_perm_select on public.shift_assignments for select to authenticated
using ( employee_id = public.perm_caller_emp_id()
        or ( public.perm_mode(auth.uid(),'shift') <> 'none'
             and public.perm_proj_ok(auth.uid(),'shift', project_id, null) ) );

create policy sa_perm_insert on public.shift_assignments for insert to authenticated
with check ( public.perm_mode(auth.uid(),'shift') = 'edit'
             and public.perm_proj_ok(auth.uid(),'shift', project_id, null) );

create policy sa_perm_update on public.shift_assignments for update to authenticated
using ( public.perm_mode(auth.uid(),'shift') = 'edit'
        and public.perm_proj_ok(auth.uid(),'shift', project_id, null) )
with check ( public.perm_mode(auth.uid(),'shift') = 'edit'
             and public.perm_proj_ok(auth.uid(),'shift', project_id, null) );

create policy sa_perm_delete on public.shift_assignments for delete to authenticated
using ( public.perm_mode(auth.uid(),'shift') = 'edit'
        and public.perm_proj_ok(auth.uid(),'shift', project_id, null) );

-- ── shift_checkins (gleiche Struktur; SELECT zusätzlich self fürs MA-Portal) ──
drop policy if exists sc_select on public.shift_checkins;
drop policy if exists sc_insert on public.shift_checkins;
drop policy if exists sc_update on public.shift_checkins;
drop policy if exists sc_delete on public.shift_checkins;

create policy sc_perm_select on public.shift_checkins for select to authenticated
using ( employee_id = public.perm_caller_emp_id()
        or ( public.perm_mode(auth.uid(),'shift') <> 'none'
             and public.perm_proj_ok(auth.uid(),'shift', project_id, null) ) );

create policy sc_perm_insert on public.shift_checkins for insert to authenticated
with check ( public.perm_mode(auth.uid(),'shift') = 'edit'
             and public.perm_proj_ok(auth.uid(),'shift', project_id, null) );

create policy sc_perm_update on public.shift_checkins for update to authenticated
using ( public.perm_mode(auth.uid(),'shift') = 'edit'
        and public.perm_proj_ok(auth.uid(),'shift', project_id, null) )
with check ( public.perm_mode(auth.uid(),'shift') = 'edit'
             and public.perm_proj_ok(auth.uid(),'shift', project_id, null) );

create policy sc_perm_delete on public.shift_checkins for delete to authenticated
using ( public.perm_mode(auth.uid(),'shift') = 'edit'
        and public.perm_proj_ok(auth.uid(),'shift', project_id, null) );

commit;

-- ── ROLLBACK (falls nötig, manuell einspielen) ──
-- update public.role_permissions set mode='read' where role_key='finance' and area_key='shift';
-- drop policy if exists sa_perm_select on public.shift_assignments;
-- drop policy if exists sa_perm_insert on public.shift_assignments;
-- drop policy if exists sa_perm_update on public.shift_assignments;
-- drop policy if exists sa_perm_delete on public.shift_assignments;
-- create policy sa_planner_all on public.shift_assignments for all to authenticated
--   using (is_admin() or (is_planner() and project_id = get_my_employee_project_id()))
--   with check (is_admin() or (is_planner() and project_id = get_my_employee_project_id()));
-- create policy sa_self_select on public.shift_assignments for select to authenticated
--   using (employee_id = get_my_employee_id());
-- drop policy if exists sc_perm_select on public.shift_checkins;
-- drop policy if exists sc_perm_insert on public.shift_checkins;
-- drop policy if exists sc_perm_update on public.shift_checkins;
-- drop policy if exists sc_perm_delete on public.shift_checkins;
-- create policy sc_select on public.shift_checkins for select to authenticated
--   using (is_admin() or (employee_id = get_my_employee_id()) or (is_planner() and project_id = get_my_employee_project_id()));
-- create policy sc_insert on public.shift_checkins for insert to authenticated
--   with check (is_admin() or (is_planner() and project_id = get_my_employee_project_id()));
-- create policy sc_update on public.shift_checkins for update to authenticated
--   using (is_admin() or (is_planner() and project_id = get_my_employee_project_id()))
--   with check (is_admin() or (is_planner() and project_id = get_my_employee_project_id()));
-- create policy sc_delete on public.shift_checkins for delete to authenticated
--   using (is_admin() or (is_planner() and project_id = get_my_employee_project_id()));
