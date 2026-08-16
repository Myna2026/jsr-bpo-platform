-- =============================================================================
-- Projektleiter/Teamleiter sehen + fuehren ihr EIGENES Projekt (RLS)   2026-08-16
-- =============================================================================
-- Anlass: Ylli Bogiqi = projektleiter Giganetz. Er braucht sein Team (lesen),
-- Abwesenheiten (schreiben), Schichten, Check-in, Performance, Bericht + Import
-- SEINES Projekts - nicht anderer. Muster ueberall: is_planner() UND
-- project_id = get_my_employee_project_id() (wie beim Check-in). Gehalt/Bank/
-- Vertrag/Ausweis + HR-interne Felder (Notizen/Verwarnungen/Dokumente) bleiben aus.
--
-- Teile: 1 employees_masked rollenbewusst (Lead-Whitelist)
--        2 employees UPDATE fuer Leads (project-scoped) + Trigger (Leads NUR absences)
--        3 shift_assignments project-scoped (schliesst die Cross-Projekt-Luecke)
--        4 Praesentation (presentations, report_fte, report_measures, presentation_comments, _templates read)
--        5 Datenimport (data_imports, weekly_hours/calls/gauges)
--        6 KPIs (kpi_project_entries write scoped, kpi_entries write scoped via Helfer)
-- Recruiting (cvs) NICHT enthalten: Bewerber haben KEINEN Projektbezug -> offene Entscheidung.
--
-- Additiv & idempotent. Im Supabase SQL-Editor ausfuehren.
-- =============================================================================

-- ── Helper ───────────────────────────────────────────────────────────────────
-- Reiner Lead (teamlead/projektleiter), NICHT gleichzeitig mgmt/hr/finance.
create or replace function public.is_lead_only()
returns boolean language sql stable security definer set search_path=public as $$
  select public.is_planner()
     and not (public.is_management() or public.is_hr() or public.is_finance());
$$;
revoke all on function public.is_lead_only() from public;
grant execute on function public.is_lead_only() to authenticated;

-- Gehoert emp_id zu MEINEM Projekt? SECURITY DEFINER, damit die Subquery nicht an
-- der employees-RLS scheitert (sonst saehe der Lead nur die eigene Zeile).
create or replace function public.is_emp_in_my_project(p_emp uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists (
    select 1 from public.employees
     where id = p_emp
       and project_id = public.get_my_employee_project_id()
  );
$$;
revoke all on function public.is_emp_in_my_project(uuid) from public;
grant execute on function public.is_emp_in_my_project(uuid) to authenticated;

-- ── 1) employees_masked: rollenbewusst ──────────────────────────────────────
-- mgmt/finance: alles. hr: alles minus Gehalt/Bank/Vertrag/Ausweis der geschuetzten MA.
-- Lead-only: WHITELIST der Fuehrungs-Felder (Rest NULL) + nur eigenes Projekt, active/training.
drop view if exists public.employees_masked;
create view public.employees_masked
with (security_invoker = false, security_barrier = true) as
select
  (jsonb_populate_record(
     null::public.employees,
     case
       when public.is_management() or public.is_finance() then to_jsonb(e)
       when public.is_hr() then
         case when public.is_protected_employee(e.id)
              then to_jsonb(e)
                   - 'fixed_salary' - 'hourly_rate' - 'salary_currency'
                   - 'bank' - 'contract' - 'id_number'
              else to_jsonb(e)
         end
       else
         jsonb_build_object(
           'id', to_jsonb(e)->'id', 'first_name', to_jsonb(e)->'first_name', 'last_name', to_jsonb(e)->'last_name',
           'position', to_jsonb(e)->'position', 'status', to_jsonb(e)->'status', 'project_id', to_jsonb(e)->'project_id',
           'role_keys', to_jsonb(e)->'role_keys', 'photo_url', to_jsonb(e)->'photo_url', 'photo_color', to_jsonb(e)->'photo_color',
           'email', to_jsonb(e)->'email', 'email_internal', to_jsonb(e)->'email_internal', 'phone', to_jsonb(e)->'phone',
           'city', to_jsonb(e)->'city', 'location', to_jsonb(e)->'location', 'language_level', to_jsonb(e)->'language_level',
           'skill', to_jsonb(e)->'skill', 'project_skill', to_jsonb(e)->'project_skill', 'primary_skill', to_jsonb(e)->'primary_skill',
           'work_hours', to_jsonb(e)->'work_hours', 'work_model', to_jsonb(e)->'work_model',
           'shift_earliest', to_jsonb(e)->'shift_earliest', 'shift_latest', to_jsonb(e)->'shift_latest',
           'allowed_shifts', to_jsonb(e)->'allowed_shifts', 'work_saturday', to_jsonb(e)->'work_saturday',
           'work_sunday', to_jsonb(e)->'work_sunday', 'work_holidays', to_jsonb(e)->'work_holidays',
           'work_weekend', to_jsonb(e)->'work_weekend', 'work_split', to_jsonb(e)->'work_split',
           'absences', to_jsonb(e)->'absences', 'vacation_days', to_jsonb(e)->'vacation_days',
           'kpi_exempt', to_jsonb(e)->'kpi_exempt', 'created_at', to_jsonb(e)->'created_at'
         )
     end
   )).*,
  (public.is_lead_only()
   or (public.is_hr() and public.is_protected_employee(e.id))) as _masked
from public.employees e
where public.is_management() or public.is_hr() or public.is_finance()
   or (public.is_planner()
       and e.project_id = public.get_my_employee_project_id()
       and e.status in ('active','training'));

grant select on public.employees_masked to authenticated;

-- ── 2) employees: Leads duerfen ihr Projekt updaten, aber NUR absences ──────
drop policy if exists employees_update_lead on public.employees;
create policy employees_update_lead on public.employees
  for update to authenticated
  using      ( public.is_planner() and project_id = public.get_my_employee_project_id() )
  with check ( public.is_planner() and project_id = public.get_my_employee_project_id() );

-- Trigger: fuer reinen Lead alles ausser absences auf OLD zuruecksetzen (nur Abwesenheiten
-- erfassbar). Bestehender HR-Gehaltsschutz bleibt.
create or replace function public.protect_salary_on_update()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_abs jsonb;
begin
  if public.is_lead_only() then
    v_abs := to_jsonb(NEW)->'absences';
    NEW := OLD;
    NEW.absences := coalesce(v_abs, OLD.absences);
    NEW.updated_at := now();
    return NEW;
  end if;
  if public.is_protected_employee(NEW.id)
     and not (public.is_management() or public.is_finance()) then
    NEW.fixed_salary    := OLD.fixed_salary;
    NEW.hourly_rate     := OLD.hourly_rate;
    NEW.salary_currency := OLD.salary_currency;
    NEW.bank            := OLD.bank;
    NEW.contract        := OLD.contract;
    NEW.id_number       := OLD.id_number;
  end if;
  return NEW;
end $$;
-- (Trigger trg_protect_salary_on_update existiert bereits und nutzt diese Funktion.)

-- ── 3) shift_assignments: project-scoped (Cross-Projekt-Luecke geschlossen) ──
drop policy if exists sa_planner_all on public.shift_assignments;
create policy sa_planner_all on public.shift_assignments
  for all to authenticated
  using      ( public.is_admin() or (public.is_planner() and project_id = public.get_my_employee_project_id()) )
  with check ( public.is_admin() or (public.is_planner() and project_id = public.get_my_employee_project_id()) );

-- ── 4) Praesentation ────────────────────────────────────────────────────────
drop policy if exists presentations_mgmt_all on public.presentations;
create policy presentations_mgmt_all on public.presentations
  for all to authenticated
  using      ( public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()) )
  with check ( public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()) );

drop policy if exists report_fte_mgmt on public.report_fte;
create policy report_fte_mgmt on public.report_fte
  for all to authenticated
  using      ( public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()) )
  with check ( public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()) );

drop policy if exists report_measures_mgmt on public.report_measures;
create policy report_measures_mgmt on public.report_measures
  for all to authenticated
  using      ( public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()) )
  with check ( public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()) );

drop policy if exists pres_comments_mgmt_all on public.presentation_comments;
create policy pres_comments_mgmt_all on public.presentation_comments
  for all to authenticated
  using      ( public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()) )
  with check ( public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()) );

-- Vorlagen sind projektuebergreifendes Design (kein project_id) -> Leads duerfen LESEN.
drop policy if exists presentation_templates_planner_read on public.presentation_templates;
create policy presentation_templates_planner_read on public.presentation_templates
  for select to authenticated using ( public.is_planner() );

-- ── 5) Datenimport ──────────────────────────────────────────────────────────
drop policy if exists data_imports_mgmt on public.data_imports;
create policy data_imports_mgmt on public.data_imports
  for all to authenticated
  using      ( public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()) )
  with check ( public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()) );

drop policy if exists weekly_hours_mgmt on public.weekly_hours;
create policy weekly_hours_mgmt on public.weekly_hours
  for all to authenticated
  using      ( public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()) )
  with check ( public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()) );

drop policy if exists weekly_calls_mgmt on public.weekly_calls;
create policy weekly_calls_mgmt on public.weekly_calls
  for all to authenticated
  using      ( public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()) )
  with check ( public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()) );

drop policy if exists weekly_gauges_mgmt on public.weekly_gauges;
create policy weekly_gauges_mgmt on public.weekly_gauges
  for all to authenticated
  using      ( public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()) )
  with check ( public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()) );

-- ── 6) KPIs ─────────────────────────────────────────────────────────────────
-- Team-KPIs (project_id vorhanden): Schreiben zusaetzlich fuer Leads des Projekts.
drop policy if exists "kpi_project_entries HR write" on public.kpi_project_entries;
create policy "kpi_project_entries HR write" on public.kpi_project_entries
  for all to authenticated
  using ( exists (select 1 from app_users where user_id=auth.uid() and role_keys && array['management','hr','finance'])
          or (public.is_planner() and project_id = public.get_my_employee_project_id()) )
  with check ( exists (select 1 from app_users where user_id=auth.uid() and role_keys && array['management','hr','finance'])
          or (public.is_planner() and project_id = public.get_my_employee_project_id()) );

-- Agenten-KPIs (kein project_id): Schreiben fuer Leads, gescoped ueber den Mitarbeiter.
-- Additiv zur bestehenden "kpi_entries HR write" (mgmt/hr/finance).
drop policy if exists kpi_entries_lead_write on public.kpi_entries;
create policy kpi_entries_lead_write on public.kpi_entries
  for all to authenticated
  using      ( public.is_planner() and public.is_emp_in_my_project(emp_id) )
  with check ( public.is_planner() and public.is_emp_in_my_project(emp_id) );
-- HINWEIS: kpi_entries LESEN ist heute breit ("read internal" fuer alle internen Rollen inkl.
-- projektleiter, NICHT projekt-gescoped). Das bleibt vorerst; eine Read-Scoping-Haertung waere
-- ein eigener Schnitt (betrifft auch mitarbeiter). Fuers Fuehren des eigenen Teams reicht der Write-Scope.

-- ── Nachweis (als Ylli/projektleiter ausfuehren) ────────────────────────────
-- 1) select count(*) from employees_masked;               -- erwartet: sein Team (z.B. 17), Gehalt NULL
-- 2) select count(*) from presentations;                  -- nur eigenes Projekt
-- 3) update employees set fixed_salary=999 where id='<teammate>';  -- Gehalt bleibt (Trigger)
-- 4) update employees set absences='[...]'::jsonb where id='<teammate>';  -- geht (Abwesenheit)

-- ── 7) Recruiting (Variante a): cvs/showcases fuer Projektleiter/Teamleiter freigeben ───────
-- OHNE Projektfilter: Bewerbungen kommen zentral herein und haben keinen Projektbezug; erst
-- die Uebernahme entscheidet das Projekt. Ein Zielprojekt-Feld waere erfunden, solange es
-- beim Eingang niemand setzt.
drop policy if exists "HR full access cvs" on public.cvs;
create policy "HR full access cvs" on public.cvs for all to authenticated
  using (exists (select 1 from public.app_users where user_id=auth.uid()
    and role_keys && array['management','hr','finance','projektleiter','teamlead']::text[]))
  with check (exists (select 1 from public.app_users where user_id=auth.uid()
    and role_keys && array['management','hr','finance','projektleiter','teamlead']::text[]));

drop policy if exists "HR full access showcases" on public.showcases;
create policy "HR full access showcases" on public.showcases for all to authenticated
  using (exists (select 1 from public.app_users where user_id=auth.uid()
    and role_keys && array['management','hr','finance','projektleiter','teamlead']::text[]))
  with check (exists (select 1 from public.app_users where user_id=auth.uid()
    and role_keys && array['management','hr','finance','projektleiter','teamlead']::text[]));
