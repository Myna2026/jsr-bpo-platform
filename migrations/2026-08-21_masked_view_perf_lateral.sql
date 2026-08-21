-- PERFORMANCE-FIX employees_masked: Masken-jsonb EINMAL pro Zeile statt 82x (Spalten-Expansion).
-- Vorher lief `select *` fuer Leads in einen 524-Timeout (jede der 82 Spaltenprojektionen baute die volle
-- CASE-Maske neu). DROP+CREATE (statt REPLACE), weil der Alt-View eine fehlbenannte Spalte '_masked' an der
-- Stelle von status_changed_at hatte -> REPLACE verbietet Umbenennen. Neu = saubere echte Spaltennamen.
-- Keine abhaengigen Objekte; Grants = Supabase-Standard, unten wiederhergestellt.
begin;
drop view if exists public.employees_masked;
create view public.employees_masked with (security_invoker=false, security_barrier=true) as
select r.*
from (
  select e.* from public.employees e
  where is_management() or is_hr() or is_finance()
     or is_planner() and e.project_id = get_my_employee_project_id() and e.status = any (array['active'::text, 'training'::text])
) e
cross join lateral ( select CASE
            WHEN is_management() OR is_finance() THEN to_jsonb(e.*)
            WHEN is_hr() THEN
            CASE
                WHEN is_protected_employee(e.id) THEN to_jsonb(e.*) - 'fixed_salary'::text - 'hourly_rate'::text - 'salary_currency'::text - 'bank'::text - 'contract'::text - 'id_number'::text
                ELSE to_jsonb(e.*)
            END
            ELSE jsonb_build_object('contract', jsonb_build_object('start', (to_jsonb(e.*) -> 'contract'::text) -> 'start'::text), 'writing_level', to_jsonb(e.*) -> 'writing_level'::text, 'languages_str', to_jsonb(e.*) -> 'languages_str'::text, 'target_role', to_jsonb(e.*) -> 'target_role'::text, 'cv_skills', to_jsonb(e.*) -> 'cv_skills'::text, 'education', to_jsonb(e.*) -> 'education'::text, 'education_level', to_jsonb(e.*) -> 'education_level'::text, 'experience_years', to_jsonb(e.*) -> 'experience_years'::text, 'quality_ratings', to_jsonb(e.*) -> 'quality_ratings'::text, 'hire_date', to_jsonb(e.*) -> 'hire_date'::text, 'termination_date', to_jsonb(e.*) -> 'termination_date'::text, 'project_assignments', to_jsonb(e.*) -> 'project_assignments'::text, 'id', to_jsonb(e.*) -> 'id'::text, 'first_name', to_jsonb(e.*) -> 'first_name'::text, 'last_name', to_jsonb(e.*) -> 'last_name'::text, 'position', to_jsonb(e.*) -> 'position'::text, 'status', to_jsonb(e.*) -> 'status'::text, 'project_id', to_jsonb(e.*) -> 'project_id'::text, 'role_keys', to_jsonb(e.*) -> 'role_keys'::text, 'photo_url', to_jsonb(e.*) -> 'photo_url'::text, 'photo_color', to_jsonb(e.*) -> 'photo_color'::text, 'email', to_jsonb(e.*) -> 'email'::text, 'email_internal', to_jsonb(e.*) -> 'email_internal'::text, 'phone', to_jsonb(e.*) -> 'phone'::text, 'city', to_jsonb(e.*) -> 'city'::text, 'location', to_jsonb(e.*) -> 'location'::text, 'language_level', to_jsonb(e.*) -> 'language_level'::text, 'skill', to_jsonb(e.*) -> 'skill'::text, 'project_skill', to_jsonb(e.*) -> 'project_skill'::text, 'primary_skill', to_jsonb(e.*) -> 'primary_skill'::text, 'work_hours', to_jsonb(e.*) -> 'work_hours'::text, 'work_model', to_jsonb(e.*) -> 'work_model'::text, 'shift_earliest', to_jsonb(e.*) -> 'shift_earliest'::text, 'shift_latest', to_jsonb(e.*) -> 'shift_latest'::text, 'allowed_shifts', to_jsonb(e.*) -> 'allowed_shifts'::text, 'work_saturday', to_jsonb(e.*) -> 'work_saturday'::text, 'work_sunday', to_jsonb(e.*) -> 'work_sunday'::text, 'work_holidays', to_jsonb(e.*) -> 'work_holidays'::text, 'work_weekend', to_jsonb(e.*) -> 'work_weekend'::text, 'work_split', to_jsonb(e.*) -> 'work_split'::text, 'absences', to_jsonb(e.*) -> 'absences'::text, 'vacation_days', to_jsonb(e.*) -> 'vacation_days'::text, 'kpi_exempt', to_jsonb(e.*) -> 'kpi_exempt'::text, 'created_at', to_jsonb(e.*) -> 'created_at'::text)
        END as j ) m
cross join lateral jsonb_populate_record(null::public.employees, m.j) r;
grant all on public.employees_masked to anon, authenticated, service_role;
commit;
