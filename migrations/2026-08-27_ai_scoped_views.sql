-- KI-Datenzugriff Schnitt 2 (Durchsetzung): gescopte Views + nlquery_ro nur noch auf diese Views.
-- Hebel: nlquery_exec laeuft als Definer nlquery_ro. Wir entziehen nlquery_ro JEDEN Tabellen-SELECT in public
-- und geben ihm ausschliesslich Schema ai_scoped (18 Views). search_path=ai_scoped -> jede nicht freigegebene
-- Tabelle ist "permission denied" bzw. "existiert nicht", egal wie die KI-SQL sie schreibt. Zeilen-/Spalten-Scope
-- steckt in den View-WHERE-Klauseln + Gehaltsmaske, gesteuert ueber GUC app.ai_uid (Aufrufer).

-- ========== Praedikate ==========
-- Kann der aktuelle GUC-Aufrufer die Datenabfrage ueberhaupt nutzen? (Back-Office-Zugang vorhanden, aktiv.)
create or replace function public.ai_can_query() returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.app_users a where a.user_id = auth.uid() and coalesce(a.active,true)) $$;

-- Aufrufer-UID aus dem JWT, als postgres-Definer (nlquery_ro braucht so keinen auth-Schemazugriff).
create or replace function public.ai_current_uid() returns uuid
language sql stable security definer set search_path=public as $$ select auth.uid() $$;

-- Sichtbarkeit einer EINZELNEN Person: Projekt-Scope + nie nach oben + Overhead/Management-Schalter + Team(Skill).
create or replace function public.ai_emp_row_ok(p_emp_id uuid, p_project text, p_skill text, p_position text)
returns boolean language plpgsql stable security definer set search_path=public as $$
declare allowed text[]; crank int; rrank int; dir text; oh boolean; cskills text[]; me uuid;
begin
  if public.ai_full() then return true; end if;
  me := (public.ai_caller_emp()).id;
  if p_emp_id is not null and p_emp_id = me then return true; end if;             -- eigene Zeile immer sichtbar
  allowed := public.ai_allowed_projects();                                        -- null = alle Projekte
  if allowed is not null and (p_project is null or not (p_project = any(allowed))) then return false; end if;
  crank := public.ai_caller_rank();
  rrank := public.ai_position_rank(p_position);
  if rrank > crank then return false; end if;                                     -- nie nach oben (nur absteigend)
  dir := coalesce(public.ai_prefs()->>'direction','down');
  if dir = 'down' and rrank = crank then return false; end if;                    -- 'down' ohne gleiche Ebene
  oh := coalesce((public.ai_prefs()->>'overhead_mgmt')::boolean, false);
  if not oh and public.ai_position_category(p_position) in ('admin','overhead') then return false; end if;
  if crank <= 30 and p_skill is not null then                                     -- Teamleiter-Ebene: nur eigener Skill
    cskills := public.ai_caller_skills();                                          -- null-Skill-Zeile bleibt sichtbar (Skill projektweit ungepflegt)
    if array_length(cskills,1) is not null and not (p_skill = any(cskills)) then return false; end if;
  end if;
  return true;
end $$;

-- Sichtbarkeit einer projektbezogenen (personenlosen) Zeile: Projekt-Scope + Team(Skill) fuer Teamleiter-Ebene.
create or replace function public.ai_proj_ok(p_project text, p_skill text default null)
returns boolean language plpgsql stable security definer set search_path=public as $$
declare allowed text[]; cskills text[];
begin
  if public.ai_full() then return true; end if;
  allowed := public.ai_allowed_projects();
  if allowed is not null and (p_project is null or not (p_project = any(allowed))) then return false; end if;
  if public.ai_caller_rank() <= 30 and p_skill is not null then
    cskills := public.ai_caller_skills();
    if array_length(cskills,1) is not null and not (p_skill = any(cskills)) then return false; end if;
  end if;
  return true;
end $$;

grant execute on function public.ai_can_query(), public.ai_current_uid(),
  public.ai_emp_row_ok(uuid,text,text,text), public.ai_proj_ok(text,text) to authenticated, service_role, nlquery_ro;

-- ========== Schema + Views ==========
create schema if not exists ai_scoped;

-- employees: Zeilen ueber ai_emp_row_ok; Gehalts-/Bankspalten maskiert, wenn ai_salary_ok(Projekt) false.
create or replace view ai_scoped.employees as
select
  e.id, e.first_name, e.last_name, e.email, e.phone, e.staff_number, e.role_keys, e.project_id, e.skill,
  e.target_role, e.status, e.source, e.cv_skills, e.hire_date, e.termination_date, e.location, e.photo_url,
  e.about_text, e.interests, e.notes,
  case when public.ai_salary_ok(e.project_id) then e.salary_type else null end as salary_type,
  case when public.ai_salary_ok(e.project_id) then e.hourly_rate else null end as hourly_rate,
  e.work_model, e.work_hours, e.shift_earliest, e.shift_latest, e.vacation_days, e.absences, e.audios, e.videos,
  e.warnings, e.project_assignments, e.allowed_shifts,
  case when public.ai_salary_ok(e.project_id) then e.bank else null end as bank,
  e.contract, e.extra, e.created_at, e.updated_at, e.abilities, e.bonuses, e.referrals, e.quality_ratings,
  e.hardware, e.position, e.city, e.id_number, e.project_skill, e.primary_skill, e.photo_color,
  case when public.ai_salary_ok(e.project_id) then e.fixed_salary else null end as fixed_salary,
  case when public.ai_salary_ok(e.project_id) then e.guaranteed_pct else null end as guaranteed_pct,
  e.deduct_missing, e.free_days_month, e.overtime_allowed, e.productive_pct, e.forecast_include,
  e.efficiency_override_pct, e.age, e.gender, e.education, e.education_level, e.experience_years, e.language_level,
  e.writing_level, e.languages_str, e.dream, e.hobbies, e.favorite_food, e.travel_wish, e.birthday,
  e.work_holidays, e.work_saturday, e.work_sunday, e.work_split, e.work_notes, e.training_id, e.staff_number_old,
  e.import_source, e.kpi_exempt, e.overhead_productive_pct, e.email_internal,
  case when public.ai_salary_ok(e.project_id) then e.salary_currency else null end as salary_currency,
  e.status_changed_at
from public.employees e
where public.ai_emp_row_ok(e.id, e.project_id, e.skill, e.position);

-- projects: nur erlaubte Projekte (projects.id = Projekt-ID).
create or replace view ai_scoped.projects as
  select p.* from public.projects p where public.ai_proj_ok(p.id);

-- Projektbezogene, personenlose Tabellen (project_id [+ skill]).
create or replace view ai_scoped.call_criteria as
  select t.* from public.call_criteria t where public.ai_proj_ok(t.project_id, t.skill);
create or replace view ai_scoped.kpi_config as
  select t.* from public.kpi_config t where public.ai_proj_ok(t.project_id, t.skill);
create or replace view ai_scoped.kpi_project_entries as
  select t.* from public.kpi_project_entries t where public.ai_proj_ok(t.project_id, t.skill);
create or replace view ai_scoped.report_forecast as
  select t.* from public.report_forecast t where public.ai_proj_ok(t.project_id, t.skill);
create or replace view ai_scoped.report_measures as
  select t.* from public.report_measures t where public.ai_proj_ok(t.project_id, t.skill);
create or replace view ai_scoped.report_longterm as
  select t.* from public.report_longterm t where public.ai_proj_ok(t.project_id, t.skill);

-- cvs: Bewerber je Projekt (kein Personen-Scope, Recruiting-Pipeline).
create or replace view ai_scoped.cvs as
  select t.* from public.cvs t where public.ai_proj_ok(t.project_id);

-- Personenbezogene Tabellen: Zeile sichtbar, wenn die zugehoerige Person sichtbar ist; personenlose
-- Aggregatzeilen (employee_id null) ueber Projekt-Scope.
create or replace view ai_scoped.call_samples as
  select t.* from public.call_samples t
  where case when t.employee_id is not null
    then exists (select 1 from public.employees e where e.id=t.employee_id
                 and public.ai_emp_row_ok(e.id,e.project_id,e.skill,e.position))
    else public.ai_proj_ok(t.project_id, t.skill) end;
create or replace view ai_scoped.shift_assignments as
  select t.* from public.shift_assignments t
  where case when t.employee_id is not null
    then exists (select 1 from public.employees e where e.id=t.employee_id
                 and public.ai_emp_row_ok(e.id,e.project_id,e.skill,e.position))
    else public.ai_proj_ok(t.project_id, t.skill) end;
create or replace view ai_scoped.weekly_hours as
  select t.* from public.weekly_hours t
  where case when t.employee_id is not null
    then exists (select 1 from public.employees e where e.id=t.employee_id
                 and public.ai_emp_row_ok(e.id,e.project_id,e.skill,e.position))
    else public.ai_proj_ok(t.project_id, t.skill) end;
create or replace view ai_scoped.weekly_calls as
  select t.* from public.weekly_calls t
  where case when t.employee_id is not null
    then exists (select 1 from public.employees e where e.id=t.employee_id
                 and public.ai_emp_row_ok(e.id,e.project_id,e.skill,e.position))
    else public.ai_proj_ok(t.project_id) end;
create or replace view ai_scoped.weekly_gauges as
  select t.* from public.weekly_gauges t
  where case when t.employee_id is not null
    then exists (select 1 from public.employees e where e.id=t.employee_id
                 and public.ai_emp_row_ok(e.id,e.project_id,e.skill,e.position))
    else public.ai_proj_ok(t.project_id) end;
create or replace view ai_scoped.report_fte as
  select t.* from public.report_fte t
  where case when t.employee_id is not null
    then exists (select 1 from public.employees e where e.id=t.employee_id
                 and public.ai_emp_row_ok(e.id,e.project_id,e.skill,e.position))
    else public.ai_proj_ok(t.project_id) end;

-- kpi_entries: nur emp_id (kein Projekt) -> ueber die Person scopen.
create or replace view ai_scoped.kpi_entries as
  select t.* from public.kpi_entries t
  where exists (select 1 from public.employees e where e.id=t.emp_id
               and public.ai_emp_row_ok(e.id,e.project_id,e.skill,e.position));

-- call_scores: haengt ueber sample_id an call_samples -> Sichtbarkeit des Samples.
create or replace view ai_scoped.call_scores as
  select t.* from public.call_scores t
  where exists (select 1 from public.call_samples cs where cs.id = t.sample_id
    and ( (cs.employee_id is not null and exists (select 1 from public.employees e where e.id=cs.employee_id
             and public.ai_emp_row_ok(e.id,e.project_id,e.skill,e.position)))
       or (cs.employee_id is null and public.ai_proj_ok(cs.project_id, cs.skill)) ));

-- windsor_marketing: Firmen-Marketing ohne Projekt/Person -> nur fuer Voll-/Alle-Projekte-Zugriffe.
create or replace view ai_scoped.windsor_marketing as
  select t.* from public.windsor_marketing t where public.ai_full() or public.ai_allowed_projects() is null;

-- ========== nlquery_ro umhaengen: weg von public-Tabellen, nur noch ai_scoped ==========
revoke select on all tables in schema public from nlquery_ro;
grant usage on schema ai_scoped to nlquery_ro;
grant select on all tables in schema ai_scoped to nlquery_ro;

-- ========== nlquery_exec: Scope per GUC, breiterer Zugang (Back-Office statt nur Management), search_path=ai_scoped ==========
create or replace function public.nlquery_exec(p_sql text) returns jsonb
language plpgsql security definer set search_path = ai_scoped as $function$
declare v text; v_res jsonb;
begin
  if not public.ai_can_query() then raise exception 'Kein Zugang zur Datenabfrage.'; end if;
  perform set_config('app.ai_uid', coalesce(public.ai_current_uid()::text,''), true);
  v := btrim(coalesce(p_sql,''));
  v := regexp_replace(v, ';+\s*$', '');
  if v = '' then raise exception 'Leere Abfrage.'; end if;
  if position(';' in v) > 0 then raise exception 'Nur eine einzelne Anweisung erlaubt.'; end if;
  if lower(v) !~ '^(with|select)\s' then raise exception 'Nur SELECT-Abfragen erlaubt.'; end if;
  if lower(v) ~ '\y(insert|update|delete|drop|alter|truncate|grant|revoke|create|merge|copy|vacuum|set|reset)\y'
    then raise exception 'Nur lesende Abfragen erlaubt (kein Schreiben).'; end if;
  set local statement_timeout = '8000';
  execute 'select coalesce(jsonb_agg(x), ''[]''::jsonb) from (select * from ('||v||') s limit 1000) x' into v_res;
  return v_res;
end $function$;
