-- Rechte Schnitt 6, Scheibe 4: Abwesenheiten-RLS auf das Modell (perm_*). Bereich 'absence'.
-- Tabelle vacation_requests (Urlaubsanträge). vacation_accounts BEWUSST NICHT (andere Reichweite: keine Leads,
-- is_protected_employee-Riegel = hr-kein-Management-Daten-Kopplung → gehört zur Mitarbeiter-/Lohn-Sensibilität).
-- employees.absences (jsonb) + vacation_days liegen AM Mitarbeiter → Mitarbeiter-Schnitt, nicht hier.
--
-- IST vacation_requests: Back-Office lesen/entscheiden = mgmt/hr/finance ALLE + Leads (is_lead_only) eigenes
-- Projekt; MA legt eigene an (pending), liest/löscht eigene. Modell bildet Back-Office nach (perm_mode + Projekt
-- des Mitarbeiters via perm_proj_ok, Skill=NULL); die MA-self-Policies (insert/delete own pending) BLEIBEN.
-- Verifiziert SELECT exakt je Rolle. FINANCE-Seed absence read->edit: IST erlaubt Finance das Entscheiden von
-- Anträgen (vacreq HR update = mgmt/hr/finance); Seed stand auf read. 0 aktive Finance-Nutzer.

begin;

update public.role_permissions set mode='edit' where role_key='finance' and area_key='absence';

-- SELECT: drei IST-Policies (HR-all / MA-self / lead-project) → eine Modell-Policy (self ODER Back-Office-Scope).
drop policy if exists "vacreq HR select all" on public.vacation_requests;
drop policy if exists "vacreq MA select own" on public.vacation_requests;
drop policy if exists "vacreq lead select project" on public.vacation_requests;

create policy vacreq_perm_select on public.vacation_requests for select to authenticated
using ( employee_id = public.perm_caller_emp_id()
        or ( public.perm_mode(auth.uid(),'absence') <> 'none'
             and public.perm_proj_ok(auth.uid(),'absence',
                  (select e.project_id from public.employees e where e.id = vacation_requests.employee_id), null) ) );

-- UPDATE (Entscheidung): zwei IST-Policies (HR / lead-project) → eine Modell-Policy (Back-Office edit-Scope, kein self).
drop policy if exists "vacreq HR update" on public.vacation_requests;
drop policy if exists "vacreq lead update project" on public.vacation_requests;

create policy vacreq_perm_update on public.vacation_requests for update to authenticated
using ( public.perm_mode(auth.uid(),'absence') = 'edit'
        and public.perm_proj_ok(auth.uid(),'absence',
             (select e.project_id from public.employees e where e.id = vacation_requests.employee_id), null) )
with check ( public.perm_mode(auth.uid(),'absence') = 'edit'
             and public.perm_proj_ok(auth.uid(),'absence',
                  (select e.project_id from public.employees e where e.id = vacation_requests.employee_id), null) );

-- INSERT (MA legt eigenen an, pending) und DELETE (MA löscht eigenen pending) bleiben unverändert.

commit;

-- ── ROLLBACK (manuell) ──
-- update public.role_permissions set mode='read' where role_key='finance' and area_key='absence';
-- drop policy if exists vacreq_perm_select on public.vacation_requests;
-- drop policy if exists vacreq_perm_update on public.vacation_requests;
-- create policy "vacreq HR select all" on public.vacation_requests for select to authenticated
--   using (exists (select 1 from app_users where user_id=auth.uid() and role_keys && array['management','hr','finance']::text[]));
-- create policy "vacreq MA select own" on public.vacation_requests for select to authenticated
--   using (employee_id = get_my_employee_id());
-- create policy "vacreq lead select project" on public.vacation_requests for select to authenticated
--   using (is_lead_only() and is_emp_in_my_project(employee_id));
-- create policy "vacreq HR update" on public.vacation_requests for update to authenticated
--   using (exists (select 1 from app_users where user_id=auth.uid() and role_keys && array['management','hr','finance']::text[]))
--   with check (exists (select 1 from app_users where user_id=auth.uid() and role_keys && array['management','hr','finance']::text[]));
-- create policy "vacreq lead update project" on public.vacation_requests for update to authenticated
--   using (is_lead_only() and is_emp_in_my_project(employee_id))
--   with check (is_lead_only() and is_emp_in_my_project(employee_id));
