-- Rechte Schnitt 6, Scheibe 5 (Mitarbeiter), TEIL A: Basis-Policies der Tabelle employees aufs Modell.
-- NUR die Basis-Tabelle. Die Maskierungs-Views (employees_masked/team_view) und der Trigger
-- protect_salary_on_update bleiben in Teil A UNANGETASTET (Zeilenfilter der Views kommen in Teil B/C).
--
-- WICHTIG: Gehaltsmaskierung ist spaltenweise → Basis-SELECT bleibt an die Gehalt-Achse gekoppelt (nur wer
-- Gehalt sehen darf, liest die Basis-Tabelle unmaskiert), sonst läse hr/Leads die Basis roh = Leak. hr/Leads
-- lesen weiter über employees_masked (Security-Definer-View, umgeht Basis-RLS). Verifiziert IST-exakt je Rolle:
-- SELECT mgmt=69(alle)/hr/Leads/MA=self; UPDATE mgmt/hr=69, Leads=26(eigenes Projekt)+self, MA=self; DELETE nur mgmt.
-- Der Trigger klemmt WAS hr/Leads ändern dürfen (Leads nur absences; hr keine Management-MA-Gehalt/Bank/Vertrag/Ausweis).
--
-- FINANCE-Seed emp read->edit: IST erlaubt Finance INSERT/UPDATE/DELETE auf employees (insert/update/delete_admin =
-- mgmt/finance/hr bzw. mgmt/finance); Seed stand auf read (unter-granted). 0 aktive Finance-Nutzer.

begin;

update public.role_permissions set mode='edit' where role_key='finance' and area_key='emp';

drop policy if exists "Employee sees own profile" on public.employees;
drop policy if exists employees_select_full on public.employees;
drop policy if exists employees_insert_admin on public.employees;
drop policy if exists employees_insert_lead on public.employees;
drop policy if exists "Employee updates own profile" on public.employees;
drop policy if exists employees_update_admin on public.employees;
drop policy if exists employees_update_lead on public.employees;
drop policy if exists employees_delete_admin on public.employees;

-- SELECT (Basis, unmaskiert): nur Gehalt-berechtigt (salary=all → mgmt/finance) ODER eigene Zeile.
create policy emp_perm_select on public.employees for select to authenticated
using ( public.perm_salary_ok(auth.uid(),'emp', id)
        or id = public.perm_caller_emp_id() );

-- INSERT: edit-Modus im erlaubten Projekt.
create policy emp_perm_insert on public.employees for insert to authenticated
with check ( public.perm_mode(auth.uid(),'emp') = 'edit'
             and public.perm_proj_ok(auth.uid(),'emp', project_id, null) );

-- UPDATE: edit-Modus im erlaubten Projekt ODER eigene Zeile. (Trigger klemmt die Spalten weiter.)
create policy emp_perm_update on public.employees for update to authenticated
using ( ( public.perm_mode(auth.uid(),'emp') = 'edit'
          and public.perm_proj_ok(auth.uid(),'emp', project_id, null) )
        or id = public.perm_caller_emp_id() )
with check ( ( public.perm_mode(auth.uid(),'emp') = 'edit'
               and public.perm_proj_ok(auth.uid(),'emp', project_id, null) )
             or id = public.perm_caller_emp_id() );

-- DELETE: nur Gehalt-berechtigt + edit (= mgmt/finance).
create policy emp_perm_delete on public.employees for delete to authenticated
using ( public.perm_salary_ok(auth.uid(),'emp', id)
        and public.perm_mode(auth.uid(),'emp') = 'edit' );

commit;

-- ── ROLLBACK (manuell) ──
-- update public.role_permissions set mode='read' where role_key='finance' and area_key='emp';
-- drop policy if exists emp_perm_select on public.employees;
-- drop policy if exists emp_perm_insert on public.employees;
-- drop policy if exists emp_perm_update on public.employees;
-- drop policy if exists emp_perm_delete on public.employees;
-- create policy "Employee sees own profile" on public.employees for select to authenticated
--   using (id = (select employee_id from app_users where user_id=auth.uid()));
-- create policy employees_select_full on public.employees for select to authenticated
--   using (is_management() or is_finance() or (id = get_my_employee_id()));
-- create policy employees_insert_admin on public.employees for insert to authenticated
--   with check (is_management() or is_finance() or is_hr());
-- create policy employees_insert_lead on public.employees for insert to authenticated
--   with check (is_planner() and (project_id = get_my_employee_project_id()));
-- create policy "Employee updates own profile" on public.employees for update to authenticated
--   using (id = (select employee_id from app_users where user_id=auth.uid()))
--   with check (id = (select employee_id from app_users where user_id=auth.uid()));
-- create policy employees_update_admin on public.employees for update to authenticated
--   using (is_management() or is_finance() or is_hr()) with check (is_management() or is_finance() or is_hr());
-- create policy employees_update_lead on public.employees for update to authenticated
--   using (is_planner() and (project_id = get_my_employee_project_id()))
--   with check (is_planner() and (project_id = get_my_employee_project_id()));
-- create policy employees_delete_admin on public.employees for delete to authenticated
--   using (is_management() or is_finance());
