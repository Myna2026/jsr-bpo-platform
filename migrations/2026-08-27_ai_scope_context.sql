-- KI-Datenzugriff Schnitt 2 (Kontext): Aufrufer als GUC app.ai_uid; STABLE-Funktionen leiten den Scope ab.
-- Projekt-IDs sind TEXT (employees.project_id/projects.id). Hierarchie aus Position+Projekt, Team = Projekt+Skill.
create or replace function public.ai_uid() returns uuid language sql stable as $$
  select nullif(current_setting('app.ai_uid', true), '')::uuid $$;

create or replace function public.ai_prefs() returns jsonb language sql stable security definer set search_path=public as $$
  select public.ai_effective_prefs(public.ai_uid()) $$;

create or replace function public.ai_full() returns boolean language sql stable security definer set search_path=public as $$
  select coalesce((public.ai_prefs()->>'full')::boolean, false) $$;

create or replace function public.ai_caller_emp() returns public.employees language sql stable security definer set search_path=public as $$
  select e.* from public.employees e join public.app_users a on a.employee_id=e.id where a.user_id=public.ai_uid() limit 1 $$;

create or replace function public.ai_caller_rank() returns int language sql stable security definer set search_path=public as $$
  select coalesce(public.ai_position_rank((public.ai_caller_emp()).position), 100) $$;

create or replace function public.ai_caller_projects() returns text[] language sql stable security definer set search_path=public as $$
  select array(select distinct pid from (
    select (public.ai_caller_emp()).project_id as pid
    union all
    select a->>'project_id' from jsonb_array_elements(coalesce((public.ai_caller_emp()).project_assignments,'[]'::jsonb)) a
      where a->>'end_date' is null
  ) s where pid is not null and pid <> '') $$;

create or replace function public.ai_caller_skills() returns text[] language sql stable security definer set search_path=public as $$
  select array(select distinct sk from (
    select (public.ai_caller_emp()).project_skill as sk
    union all
    select a->>'skill' from jsonb_array_elements(coalesce((public.ai_caller_emp()).project_assignments,'[]'::jsonb)) a where a->>'end_date' is null
  ) s where sk is not null and sk<>'') $$;

create or replace function public.ai_allowed_projects() returns text[] language sql stable security definer set search_path=public as $$
  select case (public.ai_prefs()->>'projects')
    when 'all'  then null::text[]
    when 'list' then array(select jsonb_array_elements_text(coalesce(public.ai_prefs()->'project_ids','[]'::jsonb)))
    else public.ai_caller_projects() end $$;

create or replace function public.ai_salary_ok(p_project text) returns boolean language sql stable security definer set search_path=public as $$
  select public.ai_full() or case (public.ai_prefs()->>'salaries')
    when 'all' then true
    when 'own' then p_project = any(public.ai_caller_projects())
    else false end $$;

create or replace function public.ai_position_category(p text) returns text language sql immutable as $$
  select case when p in ('Agent','Senior Agent','ASP','Supervisor') then 'agent'
    when p in ('Teamleiter','Trainer','QM','Quality Manager','Projektleiter') then 'overhead'
    else 'admin' end $$;
