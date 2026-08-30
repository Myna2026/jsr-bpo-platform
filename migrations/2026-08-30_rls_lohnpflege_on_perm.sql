-- Zurückgestellte Tabellen, Block 1: Lohnpflege (Bereich 'lohn') aufs Modell (perm_*).
-- payslips, payroll_inputs, vacation_accounts. Der Management-Schutz (is_protected_employee) bleibt als Row-Regel
-- (keine Modell-Achse). Synthetisch verifiziert (geschützt vs normal, je Rolle): payslips + vacation_accounts EXAKT;
-- payroll_inputs exakt AUSSER hr+geschützt (IST sah, Modell nicht) = bewusste KORREKTUR A (Lücke: hr konnte
-- GF-Boni/Abzüge sehen/ändern; 0 Zeilen betroffen, jetzt der richtige Zeitpunkt). B: Finance bleibt bei
-- vacation_accounts DRAUSSEN (Urlaubskonten = Personalverwaltung, nicht Buchhaltung; IST-Nachbildung).
--
-- Schutz-Ausnahme:  payslips/payroll_inputs → mgmt ODER finance dürfen Geschützte sehen (beide im Lohn drin).
--                   vacation_accounts       → nur mgmt (finance ist ganz ausgeschlossen).

begin;

-- ── payslips (employee_id; self nur lesen) ──
drop policy if exists payslips_admin_all on public.payslips;
drop policy if exists "Employee sees own payslips" on public.payslips;

create policy ps_perm_select on public.payslips for select to authenticated
using ( employee_id = public.perm_caller_emp_id()
        or ( public.perm_mode(auth.uid(),'lohn') <> 'none'
             and (not public.is_protected_employee(employee_id) or public.is_management() or public.is_finance()) ) );
create policy ps_perm_insert on public.payslips for insert to authenticated
with check ( public.perm_mode(auth.uid(),'lohn') = 'edit'
             and (not public.is_protected_employee(employee_id) or public.is_management() or public.is_finance()) );
create policy ps_perm_update on public.payslips for update to authenticated
using ( public.perm_mode(auth.uid(),'lohn') = 'edit'
        and (not public.is_protected_employee(employee_id) or public.is_management() or public.is_finance()) )
with check ( public.perm_mode(auth.uid(),'lohn') = 'edit'
             and (not public.is_protected_employee(employee_id) or public.is_management() or public.is_finance()) );
create policy ps_perm_delete on public.payslips for delete to authenticated
using ( public.perm_mode(auth.uid(),'lohn') = 'edit'
        and (not public.is_protected_employee(employee_id) or public.is_management() or public.is_finance()) );

-- ── payroll_inputs (emp_id; KEIN self; MIT Schutz = Korrektur A) ──
drop policy if exists "payroll_inputs HR write" on public.payroll_inputs;
drop policy if exists "payroll_inputs read internal" on public.payroll_inputs;

create policy pi_perm_select on public.payroll_inputs for select to authenticated
using ( public.perm_mode(auth.uid(),'lohn') <> 'none'
        and (not public.is_protected_employee(emp_id) or public.is_management() or public.is_finance()) );
create policy pi_perm_insert on public.payroll_inputs for insert to authenticated
with check ( public.perm_mode(auth.uid(),'lohn') = 'edit'
             and (not public.is_protected_employee(emp_id) or public.is_management() or public.is_finance()) );
create policy pi_perm_update on public.payroll_inputs for update to authenticated
using ( public.perm_mode(auth.uid(),'lohn') = 'edit'
        and (not public.is_protected_employee(emp_id) or public.is_management() or public.is_finance()) )
with check ( public.perm_mode(auth.uid(),'lohn') = 'edit'
             and (not public.is_protected_employee(emp_id) or public.is_management() or public.is_finance()) );
create policy pi_perm_delete on public.payroll_inputs for delete to authenticated
using ( public.perm_mode(auth.uid(),'lohn') = 'edit'
        and (not public.is_protected_employee(emp_id) or public.is_management() or public.is_finance()) );

-- ── vacation_accounts (employee_id; self; OHNE finance = Nachbildung B; Schutz-Ausnahme nur mgmt) ──
drop policy if exists va_select on public.vacation_accounts;
drop policy if exists va_insert on public.vacation_accounts;
drop policy if exists va_update on public.vacation_accounts;
drop policy if exists va_delete on public.vacation_accounts;

create policy va_perm_select on public.vacation_accounts for select to authenticated
using ( employee_id = public.perm_caller_emp_id()
        or ( public.perm_mode(auth.uid(),'lohn') <> 'none' and not public.is_finance()
             and (not public.is_protected_employee(employee_id) or public.is_management()) ) );
create policy va_perm_insert on public.vacation_accounts for insert to authenticated
with check ( public.perm_mode(auth.uid(),'lohn') = 'edit' and not public.is_finance()
             and (not public.is_protected_employee(employee_id) or public.is_management()) );
create policy va_perm_update on public.vacation_accounts for update to authenticated
using ( public.perm_mode(auth.uid(),'lohn') = 'edit' and not public.is_finance()
        and (not public.is_protected_employee(employee_id) or public.is_management()) )
with check ( public.perm_mode(auth.uid(),'lohn') = 'edit' and not public.is_finance()
             and (not public.is_protected_employee(employee_id) or public.is_management()) );
create policy va_perm_delete on public.vacation_accounts for delete to authenticated
using ( public.perm_mode(auth.uid(),'lohn') = 'edit' and not public.is_finance()
        and (not public.is_protected_employee(employee_id) or public.is_management()) );

commit;

-- ── ROLLBACK (manuell) ──
-- drop policy if exists ps_perm_select on public.payslips; drop policy if exists ps_perm_insert on public.payslips;
-- drop policy if exists ps_perm_update on public.payslips; drop policy if exists ps_perm_delete on public.payslips;
-- create policy payslips_admin_all on public.payslips for all to authenticated
--   using (is_management() or is_finance() or (is_hr() and not is_protected_employee(employee_id)))
--   with check (is_management() or is_finance() or (is_hr() and not is_protected_employee(employee_id)));
-- create policy "Employee sees own payslips" on public.payslips for select to authenticated
--   using (employee_id = (select employee_id from app_users where user_id=auth.uid()));
-- drop policy if exists pi_perm_select on public.payroll_inputs; drop policy if exists pi_perm_insert on public.payroll_inputs;
-- drop policy if exists pi_perm_update on public.payroll_inputs; drop policy if exists pi_perm_delete on public.payroll_inputs;
-- create policy "payroll_inputs HR write" on public.payroll_inputs for all to authenticated
--   using (exists(select 1 from app_users where user_id=auth.uid() and role_keys && array['management','hr','finance']::text[]))
--   with check (exists(select 1 from app_users where user_id=auth.uid() and role_keys && array['management','hr','finance']::text[]));
-- create policy "payroll_inputs read internal" on public.payroll_inputs for select to authenticated
--   using (exists(select 1 from app_users where user_id=auth.uid() and role_keys && array['management','hr','finance']::text[]));
-- drop policy if exists va_perm_select on public.vacation_accounts; drop policy if exists va_perm_insert on public.vacation_accounts;
-- drop policy if exists va_perm_update on public.vacation_accounts; drop policy if exists va_perm_delete on public.vacation_accounts;
-- create policy va_select on public.vacation_accounts for select to authenticated
--   using (is_management() or (is_hr() and not is_protected_employee(employee_id)) or (employee_id = get_my_employee_id()));
-- create policy va_insert on public.vacation_accounts for insert to authenticated
--   with check (is_management() or (is_hr() and not is_protected_employee(employee_id)));
-- create policy va_update on public.vacation_accounts for update to authenticated
--   using (is_management() or (is_hr() and not is_protected_employee(employee_id)))
--   with check (is_management() or (is_hr() and not is_protected_employee(employee_id)));
-- create policy va_delete on public.vacation_accounts for delete to authenticated
--   using (is_management() or (is_hr() and not is_protected_employee(employee_id)));
