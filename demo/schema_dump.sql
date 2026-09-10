


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."agent_guard"("p_agent" "text", "p_action" "text") RETURNS "text"
    LANGUAGE "sql" STABLE
    AS $$
  select case p_action
    when 'read' then 'autonom'
    when 'remind' then 'autonom'
    when 'slack_internal' then 'autonom'
    when 'summarize' then 'autonom'
    when 'sort_applicants' then 'autonom'
    when 'mail_external' then 'freigabe'          -- nur mit freigegebener Vorlage
    when 'applicant_decision' then 'nie'
    when 'delete' then 'nie'
    when 'money_status' then 'nie'
    when 'free_text_external' then 'nie'
    when 'judge_people' then 'nie'
    when 'promise' then 'nie'
    else 'unbekannt'
  end;
$$;


ALTER FUNCTION "public"."agent_guard"("p_agent" "text", "p_action" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."agent_missing_bank_targets"("p_actor" "uuid") RETURNS TABLE("employee_id" "uuid", "email" "text", "first_name" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select e.id, e.email, e.first_name
  from public.lena_scan() ls
  join public.employees e on e.id = ls.employee_id
  where ls.category = 'bank_fehlt'
    and public.perm_proj_ok(p_actor, 'emp', e.project_id, null)
    and coalesce(nullif(e.email,''),'') <> ''
$$;


ALTER FUNCTION "public"."agent_missing_bank_targets"("p_actor" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."agent_query_exec"("p_sql" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
declare v text; v_res jsonb;
begin
  v := btrim(coalesce(p_sql,''));
  v := regexp_replace(v, ';+\s*$', '');
  if v = '' then raise exception 'Leere Abfrage.'; end if;
  if position(';' in v) > 0 then raise exception 'Nur eine einzelne Anweisung erlaubt.'; end if;
  if lower(v) !~ '^(with|select)\s' then raise exception 'Nur SELECT-Abfragen erlaubt.'; end if;
  if lower(v) ~ '\y(insert|update|delete|drop|alter|truncate|grant|revoke|create|merge|copy|vacuum)\y'
    then raise exception 'Nur lesende Abfragen erlaubt (kein Schreiben).'; end if;
  set local statement_timeout = '8000';
  execute 'select coalesce(jsonb_agg(x), ''[]''::jsonb) from (select * from ('||v||') s limit 200) x' into v_res;
  return v_res;
end $_$;


ALTER FUNCTION "public"."agent_query_exec"("p_sql" "text") OWNER TO "agent_ro";


CREATE OR REPLACE FUNCTION "public"."agent_recipients"("p_project" "text", "p_area" "text", "p_roles" "text"[]) RETURNS SETOF "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select u.user_id from public.app_users u
  where u.active is not false
    and u.role_keys && p_roles
    and public.perm_proj_ok(u.user_id, p_area, p_project, null)
$$;


ALTER FUNCTION "public"."agent_recipients"("p_project" "text", "p_area" "text", "p_roles" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_access_overview"() RETURNS TABLE("user_id" "uuid", "full_name" "text", "email" "text", "role_keys" "text"[], "employee_id" "uuid", "is_full" boolean, "stored" "jsonb", "default_prefs" "jsonb", "effective" "jsonb")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select a.user_id, a.full_name, u.email, a.role_keys, a.employee_id,
    public.ai_is_full(a.user_id),
    (select p.settings from public.ai_access_prefs p where p.user_id = a.user_id),
    public.ai_default_prefs(a.user_id),
    public.ai_effective_prefs(a.user_id)
  from public.app_users a
  left join auth.users u on u.id = a.user_id
  where coalesce(a.active, true) and public.is_management()
    and array_length(a.role_keys, 1) is not null
    and not ('kunde' = any(a.role_keys))
$$;


ALTER FUNCTION "public"."ai_access_overview"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_allowed_projects"() RETURNS "text"[]
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select case (public.ai_prefs()->>'projects')
    when 'all'  then null::text[]
    when 'list' then array(select jsonb_array_elements_text(coalesce(public.ai_prefs()->'project_ids','[]'::jsonb)))
    else public.ai_caller_projects() end $$;


ALTER FUNCTION "public"."ai_allowed_projects"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."employees" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "first_name" "text" NOT NULL,
    "last_name" "text" NOT NULL,
    "email" "text",
    "phone" "text",
    "staff_number" "text",
    "role_keys" "text"[] DEFAULT ARRAY[]::"text"[],
    "project_id" "text",
    "skill" "text",
    "target_role" "text",
    "status" "text" DEFAULT 'active'::"text",
    "source" "text" DEFAULT 'manual'::"text",
    "cv_skills" "text"[] DEFAULT ARRAY[]::"text"[],
    "hire_date" "date",
    "termination_date" "date",
    "location" "text",
    "photo_url" "text",
    "about_text" "text",
    "interests" "text"[] DEFAULT ARRAY[]::"text"[],
    "notes" "text",
    "salary_type" "text",
    "hourly_rate" numeric,
    "work_model" "text",
    "work_hours" numeric,
    "shift_earliest" "text",
    "shift_latest" "text",
    "vacation_days" numeric,
    "absences" "jsonb" DEFAULT '[]'::"jsonb",
    "audios" "jsonb" DEFAULT '[]'::"jsonb",
    "videos" "jsonb" DEFAULT '[]'::"jsonb",
    "warnings" "jsonb" DEFAULT '[]'::"jsonb",
    "project_assignments" "jsonb" DEFAULT '[]'::"jsonb",
    "allowed_shifts" "jsonb" DEFAULT '[]'::"jsonb",
    "bank" "jsonb" DEFAULT '{}'::"jsonb",
    "contract" "jsonb" DEFAULT '{}'::"jsonb",
    "extra" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "abilities" "jsonb" DEFAULT '[]'::"jsonb",
    "bonuses" "jsonb" DEFAULT '[]'::"jsonb",
    "referrals" "jsonb" DEFAULT '[]'::"jsonb",
    "quality_ratings" "jsonb" DEFAULT '[]'::"jsonb",
    "hardware" "jsonb" DEFAULT '[]'::"jsonb",
    "position" "text",
    "city" "text",
    "id_number" "text",
    "project_skill" "text",
    "primary_skill" "text",
    "photo_color" "text",
    "fixed_salary" numeric,
    "guaranteed_pct" numeric,
    "deduct_missing" boolean,
    "free_days_month" integer,
    "overtime_allowed" boolean,
    "productive_pct" numeric,
    "forecast_include" boolean,
    "efficiency_override_pct" numeric,
    "age" integer,
    "gender" "text",
    "education" "text",
    "education_level" "text",
    "experience_years" integer,
    "language_level" "text",
    "writing_level" "text",
    "languages_str" "text",
    "dream" "text",
    "hobbies" "text",
    "favorite_food" "text",
    "travel_wish" "text",
    "birthday" "date",
    "work_holidays" boolean,
    "work_saturday" boolean,
    "work_sunday" boolean,
    "work_split" boolean,
    "work_notes" "text",
    "training_id" "text",
    "staff_number_old" "text",
    "import_source" "text",
    "kpi_exempt" boolean DEFAULT false,
    "overhead_productive_pct" numeric DEFAULT 0,
    "email_internal" "text",
    "salary_currency" "text",
    "status_changed_at" timestamp with time zone
);


ALTER TABLE "public"."employees" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_caller_emp"() RETURNS "public"."employees"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select e.* from public.employees e join public.app_users a on a.employee_id=e.id where a.user_id=public.ai_uid() limit 1 $$;


ALTER FUNCTION "public"."ai_caller_emp"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_caller_projects"() RETURNS "text"[]
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select array(select distinct pid from (
    select (public.ai_caller_emp()).project_id as pid
    union all
    select a->>'project_id' from jsonb_array_elements(coalesce((public.ai_caller_emp()).project_assignments,'[]'::jsonb)) a
      where a->>'end_date' is null
  ) s where pid is not null and pid <> '') $$;


ALTER FUNCTION "public"."ai_caller_projects"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_caller_rank"() RETURNS integer
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(public.ai_position_rank((public.ai_caller_emp()).position), 100) $$;


ALTER FUNCTION "public"."ai_caller_rank"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_caller_skills"() RETURNS "text"[]
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select array(select distinct sk from (
    select (public.ai_caller_emp()).project_skill as sk
    union all
    select a->>'skill' from jsonb_array_elements(coalesce((public.ai_caller_emp()).project_assignments,'[]'::jsonb)) a where a->>'end_date' is null
  ) s where sk is not null and sk<>'') $$;


ALTER FUNCTION "public"."ai_caller_skills"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_can_query"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists(select 1 from public.app_users a where a.user_id = auth.uid() and coalesce(a.active,true)) $$;


ALTER FUNCTION "public"."ai_can_query"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_current_uid"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$ select auth.uid() $$;


ALTER FUNCTION "public"."ai_current_uid"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_default_prefs"("p_uid" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare rk text[];
begin
  select coalesce(role_keys,'{}') into rk from public.app_users where user_id = p_uid;
  if rk && array['management','finance'] then
    return '{"projects":"all","project_ids":[],"direction":"side","salaries":"all","overhead_mgmt":true}'::jsonb;
  elsif 'hr' = any(rk) then
    return '{"projects":"all","project_ids":[],"direction":"side","salaries":"none","overhead_mgmt":true}'::jsonb;
  elsif 'projektleiter' = any(rk) then
    return '{"projects":"own","project_ids":[],"direction":"side","salaries":"none","overhead_mgmt":true}'::jsonb;
  elsif 'teamleiter' = any(rk) then
    return '{"projects":"own","project_ids":[],"direction":"down","salaries":"none","overhead_mgmt":false}'::jsonb;
  else
    return '{"projects":"own","project_ids":[],"direction":"down","salaries":"none","overhead_mgmt":false}'::jsonb;
  end if;
end $$;


ALTER FUNCTION "public"."ai_default_prefs"("p_uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_effective_prefs"("p_uid" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare s jsonb;
begin
  if p_uid is null then return '{"projects":"none"}'::jsonb; end if;
  if public.ai_is_full(p_uid) then
    return '{"full":true,"projects":"all","project_ids":[],"direction":"side","salaries":"all","overhead_mgmt":true}'::jsonb;
  end if;
  select settings into s from public.ai_access_prefs where user_id = p_uid;
  if s is null or s = '{}'::jsonb then return public.ai_default_prefs(p_uid); end if;
  return public.ai_default_prefs(p_uid) || s;   -- gespeicherte Werte überschreiben Defaults
end $$;


ALTER FUNCTION "public"."ai_effective_prefs"("p_uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_emp_row_ok"("p_emp_id" "uuid", "p_project" "text", "p_skill" "text", "p_position" "text") RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."ai_emp_row_ok"("p_emp_id" "uuid", "p_project" "text", "p_skill" "text", "p_position" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_full"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce((public.ai_prefs()->>'full')::boolean, false) $$;


ALTER FUNCTION "public"."ai_full"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_is_full"("p_uid" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1 from auth.users u where u.id = p_uid
      and lower(u.email) = any (array['info@mynaai.de','sh.cikaqi@25hrs.net','r.gore@tiramu.de','consulting@25hrs.net'])
  );
$$;


ALTER FUNCTION "public"."ai_is_full"("p_uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_position_category"("p" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select case when p in ('Agent','Senior Agent','ASP','Supervisor') then 'agent'
    when p in ('Teamleiter','Trainer','QM','Quality Manager','Projektleiter') then 'overhead'
    else 'admin' end $$;


ALTER FUNCTION "public"."ai_position_category"("p" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_position_rank"("p_pos" "text") RETURNS integer
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select case
    when p_pos in ('Management','Finance','HR','IT') then 100
    when p_pos = 'Projektleiter' then 40
    when p_pos in ('Teamleiter','Trainer','QM','Quality Manager') then 30
    when p_pos = 'Supervisor' then 20
    when p_pos in ('Senior Agent','ASP') then 12
    when p_pos = 'Agent' then 10
    else 15 end;
$$;


ALTER FUNCTION "public"."ai_position_rank"("p_pos" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_prefs"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select public.ai_effective_prefs(public.ai_uid()) $$;


ALTER FUNCTION "public"."ai_prefs"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_proj_ok"("p_project" "text", "p_skill" "text" DEFAULT NULL::"text") RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."ai_proj_ok"("p_project" "text", "p_skill" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_salary_ok"("p_project" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select public.ai_full() or case (public.ai_prefs()->>'salaries')
    when 'all' then true
    when 'own' then p_project = any(public.ai_caller_projects())
    else false end $$;


ALTER FUNCTION "public"."ai_salary_ok"("p_project" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_scope_overview"() RETURNS TABLE("user_id" "uuid", "email" "text", "is_full" boolean, "projects" "text", "project_ids" "jsonb", "direction" "text", "salary" "text", "overhead" boolean)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not exists(select 1 from public.app_users
                where user_id=auth.uid() and active and role_keys && array['management']::text[]) then
    raise exception 'nur management';
  end if;
  return query
  select u.user_id, u.email,
    (public.perm_allowed_projects(u.user_id,'emp') is null
       and coalesce(public.perm(u.user_id,'emp')->>'salary','none')='all'
       and public.perm_overhead_ok(u.user_id))                             as is_full,
    coalesce(public.perm(u.user_id,'emp')->>'projects','own')              as projects,
    coalesce(public.perm(u.user_id,'emp')->'project_ids','[]'::jsonb)      as project_ids,
    coalesce(public.perm(u.user_id,'emp')->>'direction','down')           as direction,
    coalesce(public.perm(u.user_id,'emp')->>'salary','none')              as salary,
    public.perm_overhead_ok(u.user_id)                                     as overhead
  from public.app_users u
  where u.active and array_length(u.role_keys,1) is not null
    and not (u.role_keys && array['kunde']::text[]);
end $$;


ALTER FUNCTION "public"."ai_scope_overview"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_uid"() RETURNS "uuid"
    LANGUAGE "sql" STABLE
    AS $$
  select nullif(current_setting('app.ai_uid', true), '')::uuid $$;


ALTER FUNCTION "public"."ai_uid"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_checkout_daily"("target" "date" DEFAULT NULL::"date") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare d date; n integer;
begin
  d := coalesce(target, (now() at time zone 'Europe/Berlin')::date);
  with planned as (
    select sc.project_id, sc.skill, sc.employee_id, sc.work_date, sc.source,
           (select max((mm[1])::time)
              from regexp_matches(
                     concat_ws(' ', sa.shift_value, sa.label,
                               sa.shift->>'shift', sa.shift->>'label',
                               sa.shift->>'split_morning', sa.shift->>'split_afternoon'),
                     '(\d{1,2}:\d{2})', 'g') as mm) as end_t
    from public.shift_checkins sc
    join public.shift_assignments sa
      on  sa.project_id  = sc.project_id
      and sa.skill       = sc.skill
      and sa.employee_id = sc.employee_id
      and sa.work_date   = sc.work_date
    where sc.work_date = d
      and sc.departure is null
      and sc.status in ('present','late','early')
  )
  update public.shift_checkins sc
     set departure = p.end_t, departure_source = 'auto', updated_at = now()
    from planned p
   where sc.project_id  = p.project_id
     and sc.skill       = p.skill
     and sc.employee_id = p.employee_id
     and sc.work_date   = p.work_date
     and sc.source      = p.source
     and p.end_t is not null;
  get diagnostics n = row_count;
  return n;
end $$;


ALTER FUNCTION "public"."auto_checkout_daily"("target" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calendar_event_visible"("ev" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1 from public.calendar_events e
    where e.id = ev
      and ( public.is_admin()
            or e.created_by = auth.uid()
            or public.get_my_employee_id() = any(e.participants)
            or (e.visible_roles <> '{}'::text[] and e.visible_roles && public.get_my_role_keys()) )
  );
$$;


ALTER FUNCTION "public"."calendar_event_visible"("ev" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."chat_is_monitored"("p_emp" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare cfg jsonb; proj text;
begin
  if p_emp is null then return false; end if;
  select value into cfg from public.app_config where key='jsr_chat_monitoring_v1';
  if cfg is null then return false; end if;
  if coalesce((cfg->>'global')::boolean, false) then return true; end if;
  select project_id::text into proj from public.employees where id = p_emp;
  if proj is not null and exists (select 1 from jsonb_array_elements_text(coalesce(cfg->'projects','[]'::jsonb)) x where x = proj) then
    return true;
  end if;
  if exists (select 1 from jsonb_array_elements_text(coalesce(cfg->'employees','[]'::jsonb)) x where x = p_emp::text) then
    return true;
  end if;
  return false;
end $$;


ALTER FUNCTION "public"."chat_is_monitored"("p_emp" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."chat_monitoring_status"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select public.chat_is_monitored(public.get_my_employee_id());
$$;


ALTER FUNCTION "public"."chat_monitoring_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."clara_handover_scan"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  cfg jsonb; hand int; hcap int; p1 boolean; p2 boolean;
  v_new int := 0; v_res int := 0; r record;
begin
  select value into cfg from app_config where key='jsr_clara_auto_v1';
  if cfg is null then return jsonb_build_object('ok',false,'msg','keine Config'); end if;
  hand := coalesce((cfg->'windows'->>'handover_workdays')::int, 3);
  hcap := coalesce((cfg->'windows'->>'hard_cap_workdays')::int, 5);
  p1 := coalesce((cfg->'phases'->'phase1'->>'enabled')::boolean, false);
  p2 := coalesce((cfg->'phases'->'phase2'->>'enabled')::boolean, false);

  -- Auto-Resolve: Bewerber hat die Phase verlassen (weiter/abgelehnt/übernommen) ODER reagiert.
  update public.clara_handovers h set resolved_at=now()
   where h.resolved_at is null and (
     not exists (select 1 from public.cvs c where c.id=h.cv_id and c.status in ('cv_inbound','cv_confirmed'))
     or (h.phase='phase1' and exists (select 1 from public.cv_enrich_invites e where e.cv_id=h.cv_id and e.used_at is not null))
     or (h.phase='phase2' and exists (select 1 from public.interview_invites i where i.cv_id=h.cv_id and i.status='booked'))
   );
  get diagnostics v_res = row_count;

  for r in select c.id, c.status, c.email, c.status_changed_at, c.created_at
             from public.cvs c where c.status in ('cv_inbound','cv_confirmed') loop
    if (r.status='cv_inbound' and not p1) or (r.status='cv_confirmed' and not p2) then continue; end if;
    if exists (select 1 from public.clara_handovers h where h.cv_id=r.id and h.resolved_at is null) then continue; end if;
    declare
      v_reason text := null;
      v_phase text := case when r.status='cv_inbound' then 'phase1' else 'phase2' end;
    begin
      if nullif(btrim(coalesce(r.email,'')),'') is null then
        v_reason := 'no_email';
      elsif r.status='cv_inbound' then
        if exists (select 1 from public.cv_enrich_invites e where e.cv_id=r.id and e.used_at is null and clara_workdays_since(e.created_at) >= hand) then v_reason := 'no_completion'; end if;
      elsif r.status='cv_confirmed' then
        if exists (select 1 from public.interview_invites i where i.cv_id=r.id and i.status<>'booked' and clara_workdays_since(i.created_at) >= hand) then v_reason := 'no_booking'; end if;
      end if;
      if v_reason is null and clara_workdays_since(coalesce(r.status_changed_at, r.created_at)) >= hcap then v_reason := 'hard_cap'; end if;
      if v_reason is not null then
        insert into public.clara_handovers(cv_id, reason, phase) values (r.id, v_reason, v_phase)
          on conflict (cv_id) where resolved_at is null do nothing;
        v_new := v_new + 1;
      end if;
    end;
  end loop;

  return jsonb_build_object('ok',true,'neu',v_new,'aufgeloest',v_res);
end $$;


ALTER FUNCTION "public"."clara_handover_scan"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."clara_marketing_scan"() RETURNS TABLE("category" "text", "subject" "text", "detail" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  d date := (now() at time zone 'Europe/Berlin')::date;
  cur_mon  date := date_trunc('week', d)::date - 7;    -- Montag letzte (abgeschlossene) Woche
  prev_mon date := date_trunc('week', d)::date - 14;
begin
  return query
  -- 1) Qualität: TOP/GUT letzte Woche vs Vorwoche
  with q as (
    select
      case when created_at::date >= cur_mon  and created_at::date < cur_mon+7  then 'cur'
           when created_at::date >= prev_mon and created_at::date < prev_mon+7 then 'prev' end as wk,
      (case when upper(coalesce(nullif(language_level,''), extra->>'german','')) ~ 'C1|C2|MUTTERSPRACH' then 'C1'
            when upper(coalesce(nullif(language_level,''), extra->>'german','')) ~ 'B2' then 'B2' else '' end) as lang,
      (case when lower(coalesce(extra->>'cc_experience','')) ~ '^(nein|no|kein|nicht)' then false
            when lower(coalesce(extra->>'cc_experience','')) ~ '(ja|yes|jo|jahr|erfahr|agent|service|call|verkauf|[0-9])' then true end) as exp
    from public.cvs where created_at::date >= prev_mon and created_at::date < cur_mon+7
  ),
  qc as (
    select wk,
      count(*) filter (where lang='C1' and exp is true) as top,
      count(*) filter (where not (lang='C1' and exp is true) and (lang='C1' or (lang='B2' and exp is true))) as gut,
      count(*) as total
    from q where wk is not null group by wk
  ),
  qq as (
    select coalesce((select top from qc where wk='cur'),0) tc, coalesce((select gut from qc where wk='cur'),0) gc, coalesce((select total from qc where wk='cur'),0) nc,
           coalesce((select top from qc where wk='prev'),0) tp, coalesce((select gut from qc where wk='prev'),0) gp, coalesce((select total from qc where wk='prev'),0) np
  )
  select 'qualitaet'::text, 'Zulauf-Qualität letzte Woche',
    'diese Woche '||tc||' TOP / '||gc||' GUT von '||nc||', Vorwoche '||tp||' / '||gp||' von '||np||' — '||
    (case when (tc+gc) > (tp+gp) then 'die Qualität steigt, mehr taugliche Bewerbungen'
          when (tc+gc) < (tp+gp) then 'die Qualität fällt: viele billige Bewerbungen sind nichts wert, wenn keine davon taugt'
          else 'die Qualität bleibt gleich' end)
    from qq
  union all
  -- 2) Kampagne: Klickpreis (Spend/Klicks) deutlich verändert (>25%, beide Wochen mit Daten)
  select 'kampagne', c.campaign,
    'Klickpreis von €'||to_char(c.cpc_prev,'FM990.00')||' auf €'||to_char(c.cpc_cur,'FM990.00')||' ('
      ||(case when c.cpc_cur>c.cpc_prev then '+' else '' end)||round((c.cpc_cur-c.cpc_prev)/c.cpc_prev*100)||'%) — '
      ||(case when c.cpc_cur>c.cpc_prev then 'teurer, gleiche Menge kostet mehr' else 'günstiger, mehr fürs Geld' end)
    from (
      select campaign,
        sum(spend) filter (where date>=cur_mon  and date<cur_mon+7)  / nullif(sum(clicks) filter (where date>=cur_mon  and date<cur_mon+7),0)  as cpc_cur,
        sum(spend) filter (where date>=prev_mon and date<prev_mon+7) / nullif(sum(clicks) filter (where date>=prev_mon and date<prev_mon+7),0) as cpc_prev
      from public.windsor_marketing where campaign is not null and campaign<>'' group by campaign
    ) c
    where c.cpc_cur is not null and c.cpc_prev is not null and c.cpc_prev>0 and abs(c.cpc_cur-c.cpc_prev)/c.cpc_prev > 0.25
  union all
  -- 3) daten_fehlt: Kampagne lief Vorwoche mit Spend, jetzt Woche ohne jede Zeile
  select 'daten_fehlt', c.campaign,
    'lief in der Vorwoche (€'||to_char(c.sp_prev,'FM990.00')||' Spend), diese Woche keine Daten mehr — Windsor liefert für sie nichts, die Wirkung ist blind'
    from (
      select campaign,
        sum(spend) filter (where date>=prev_mon and date<prev_mon+7) as sp_prev,
        count(*)   filter (where date>=cur_mon  and date<cur_mon+7)  as rows_cur
      from public.windsor_marketing where campaign is not null and campaign<>'' group by campaign
    ) c
    where coalesce(c.sp_prev,0) > 0 and coalesce(c.rows_cur,0) = 0;
end $$;


ALTER FUNCTION "public"."clara_marketing_scan"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."clara_morning_stats"("p_date" "date" DEFAULT CURRENT_DATE) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_new int; v_prev int; v_rep int; v_exp int; v_dub int;
  v_hoch int; v_mittel int; v_niedrig int; v_unb int;
  v_top int; v_gut int; v_rest int;
begin
  if auth.uid() is not null and not public.is_admin() then raise exception 'not authorized'; end if;

  select count(*) into v_new  from public.cvs where created_at::date = p_date;
  select count(*) into v_prev from public.cvs where created_at::date = p_date - 1;

  select count(*) into v_rep from public.cvs t
   where t.created_at::date = p_date
     and exists (select 1 from public.cvs o where o.id <> t.id and o.created_at < p_date::timestamp
        and ((t.email is not null and t.email<>'' and lower(o.email)=lower(t.email))
          or (t.phone is not null and t.phone<>'' and o.phone=t.phone)));

  select
    count(*) filter (where language_level in ('C1','C2') or language_level ilike '%mutter%'),
    count(*) filter (where language_level in ('B1','B2')),
    count(*) filter (where language_level in ('A1','A2')),
    count(*) filter (where language_level is null or language_level=''),
    count(*) filter (where experience_years is not null)
  into v_hoch, v_mittel, v_niedrig, v_unb, v_exp
  from public.cvs where created_at::date = p_date;

  -- Qualität (TOP/GUT/Rest) nach der Kanban-/Listen-Regel.
  with c as (
    select
      case when upper(coalesce(nullif(language_level,''), extra->>'german','')) ~ 'C1|C2|MUTTERSPRACH' then 'C1'
           when upper(coalesce(nullif(language_level,''), extra->>'german','')) ~ 'B2' then 'B2'
           when upper(coalesce(nullif(language_level,''), extra->>'german','')) ~ 'B1' then 'B1' else '' end as lang,
      case when lower(trim(coalesce(extra->>'cc_experience',''))) = '' then null
           when lower(coalesce(extra->>'cc_experience','')) ~ '^(nein|no|kein|nicht)' then false
           when lower(coalesce(extra->>'cc_experience','')) ~ '(ja|yes|jo|jahr|erfahr|agent|service|call|verkauf|[0-9])' then true
           else null end as exp
    from public.cvs where created_at::date = p_date)
  select
    count(*) filter (where lang='C1' and exp is true),
    count(*) filter (where not (lang='C1' and exp is true) and (lang='C1' or (lang='B2' and exp is true)))
  into v_top, v_gut from c;
  v_rest := greatest(0, v_new - v_top - v_gut);

  select count(*) into v_dub from public.cvs c
   where c.status in ('cv_inbound','cv_accepted','cv_confirmed','invited','no_contact','parking')
     and exists (select 1 from public.cvs o where o.id <> c.id
        and ((c.email is not null and c.email<>'' and lower(o.email)=lower(c.email))
          or (c.phone is not null and c.phone<>'' and o.phone=c.phone)));

  return jsonb_build_object(
    'new_today', v_new, 'new_prev', v_prev, 'repeaters', v_rep,
    'lang', jsonb_build_object('hoch',v_hoch,'mittel',v_mittel,'niedrig',v_niedrig,'unbekannt',v_unb),
    'quality', jsonb_build_object('top',v_top,'gut',v_gut,'rest',v_rest),
    'has_experience', v_exp, 'dubletten_pending', v_dub);
end $$;


ALTER FUNCTION "public"."clara_morning_stats"("p_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."clara_schedule_rejection"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare cfg jsonb; delay int;
begin
  if NEW.status is not distinct from OLD.status then return NEW; end if;
  if NEW.status not in ('rejected_by_us','rejected_by_client','no_contact') then return NEW; end if;
  select value into cfg from app_config where key='jsr_clara_auto_v1';
  if not coalesce((cfg->'rejects'->NEW.status->>'enabled')::boolean, false) then return NEW; end if;
  if exists (select 1 from public.clara_rejections r where r.cv_id=NEW.id and r.sent_at is null and r.cancelled_at is null) then return NEW; end if;
  delay := coalesce((cfg->>'reject_delay_hours')::int, 48);
  insert into public.clara_rejections(cv_id, reject_status, due_at)
    values (NEW.id, NEW.status, now() + make_interval(hours => delay));
  return NEW;
end $$;


ALTER FUNCTION "public"."clara_schedule_rejection"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."clara_workdays_since"("p_ts" timestamp with time zone) RETURNS integer
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
  select case when p_ts is null then 9999 else (
    select count(*)::int from generate_series(
      ((p_ts at time zone 'Europe/Berlin')::date + 1),
      ((now() at time zone 'Europe/Berlin')::date),
      interval '1 day') d
    where extract(isodow from d) between 1 and 5
  ) end;
$$;


ALTER FUNCTION "public"."clara_workdays_since"("p_ts" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."clear_must_change_pw"() RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare n integer;
begin
  update public.app_users
     set must_change_pw = false
   where user_id = auth.uid();
  get diagnostics n = row_count;
  return n > 0;
end $$;


ALTER FUNCTION "public"."clear_must_change_pw"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."client_meeting_prep"("p_project" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare d date := (now() at time zone 'Europe/Berlin')::date;
        cur_yw int := extract(isoyear from d)::int*100 + extract(week from d)::int;
        lo_yw int := cur_yw - 6;   -- ~6 KWs zurück (innerhalb desselben Jahres sauber; Jahreswechsel unscharf)
begin
  if not (public.is_management() or (public.is_planner() and p_project = public.get_my_employee_project_id())) then
    return jsonb_build_object('error','nicht berechtigt');
  end if;

  return jsonb_build_object(
    'project', p_project,
    'project_name', (select name from public.projects where id=p_project),
    'generated_yw', cur_yw,
    -- Kennzahlen je Skill: Reihe (KW->Team-Schnitt) + letzter/vorheriger Wert + Richtung
    'kpis', (
      select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
        select s.skill, s.kpi, s.unit,
          (select jsonb_object_agg(w.yw, w.avg_val) from (
             select ke.year*100+ke.kw as yw, round(avg(ke.value)::numeric,2) as avg_val
             from public.kpi_entries ke join public.employees e on e.id=ke.emp_id
             where e.project_id=p_project and ke.kpi_id=s.kpi_id and ke.year*100+ke.kw between lo_yw and cur_yw
             group by ke.year*100+ke.kw) w) as series,
          (select round(avg(ke.value)::numeric,2) from public.kpi_entries ke join public.employees e on e.id=ke.emp_id
             where e.project_id=p_project and ke.kpi_id=s.kpi_id and ke.year*100+ke.kw=(
               select max(ke2.year*100+ke2.kw) from public.kpi_entries ke2 join public.employees e2 on e2.id=ke2.emp_id
               where e2.project_id=p_project and ke2.kpi_id=s.kpi_id and ke2.year*100+ke2.kw<=cur_yw)) as latest,
          (select round(avg(ke.value)::numeric,2) from public.kpi_entries ke join public.employees e on e.id=ke.emp_id
             where e.project_id=p_project and ke.kpi_id=s.kpi_id and ke.year*100+ke.kw=(
               select max(ke2.year*100+ke2.kw) from public.kpi_entries ke2 join public.employees e2 on e2.id=ke2.emp_id
               where e2.project_id=p_project and ke2.kpi_id=s.kpi_id and ke2.year*100+ke2.kw<cur_yw and ke2.year*100+ke2.kw<(
                 select max(ke3.year*100+ke3.kw) from public.kpi_entries ke3 join public.employees e3 on e3.id=ke3.emp_id
                 where e3.project_id=p_project and ke3.kpi_id=s.kpi_id and ke3.year*100+ke3.kw<=cur_yw))) as prev
        from (
          select distinct kc.id as kpi_id, kc.name as kpi, lower(kc.skill) as skill, kc.unit
          from public.kpi_config kc
          where coalesce(kc.level,'agent')<>'team'
            and exists (select 1 from public.kpi_entries ke join public.employees e on e.id=ke.emp_id
                        where e.project_id=p_project and ke.kpi_id=kc.id)
        ) s order by s.skill, s.kpi
      ) x
    ),
    -- Forecast letzte Wochen je Skill (Bedarf) + Ist-Stunden falls vorhanden
    'forecast', (
      select coalesce(jsonb_agg(jsonb_build_object('skill',rf.skill,'yw',rf.year*100+rf.kw,'fc_hours',round(rf.fc_hours::numeric,1)) order by rf.skill, rf.year*100+rf.kw), '[]'::jsonb)
      from public.report_forecast rf where rf.project_id=p_project and rf.year*100+rf.kw between lo_yw and cur_yw and rf.fc_hours>0
    ),
    -- Call-Qualität: Team-AHT (gewichtet nach answered) + answered je letzter Wochen
    'calls', (
      select coalesce(jsonb_agg(row_to_json(c)), '[]'::jsonb) from (
        select wc.year*100+wc.kw as yw, sum(wc.answered) as answered,
          round((sum(wc.avg_handle_sec*wc.answered)/nullif(sum(wc.answered),0))::numeric,0) as aht_sec
        from public.weekly_calls wc where wc.project_id=p_project and wc.year*100+wc.kw between lo_yw and cur_yw
        group by wc.year*100+wc.kw order by wc.year*100+wc.kw) c
    ),
    -- Besetzung je Skill (aktiv)
    'staffing', (
      select coalesce(jsonb_object_agg(sk, n), '{}'::jsonb) from (
        select lower(project_skill) as sk, count(*) as n from public.employees
        where project_id=p_project and status in ('active','training') and project_skill is not null group by lower(project_skill)) q
    ),
    -- anstehende Abwesenheiten (nächste 14 Tage)
    'absences_soon', (
      select coalesce(jsonb_agg(jsonb_build_object('name', e.first_name||' '||e.last_name, 'skill', lower(e.project_skill),
               'type', a->>'type', 'from', a->>'from', 'to', coalesce(nullif(a->>'to',''), a->>'from')) ), '[]'::jsonb)
      from public.employees e, jsonb_array_elements(coalesce(e.absences,'[]'::jsonb)) a
      where e.project_id=p_project and (a->>'from') ~ '^\d{4}-\d{2}-\d{2}'
        and (a->>'from')::date <= d+14 and coalesce(nullif(a->>'to',''),(a->>'from'))::date >= d
    )
  );
end $$;


ALTER FUNCTION "public"."client_meeting_prep"("p_project" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."confirm_interview_slot"("p_token" "text", "p_slot" "text", "p_form" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  inv public.interview_invites%rowtype;
  v_name text; cfg jsonb; v_start time; v_end time; v_slot int; v_win int; v_lead int; v_today date;
  s_ts timestamp; s_date date; s_time time; ev_id uuid;
begin
  select * into inv from public.interview_invites where token = p_token;
  if not found then return jsonb_build_object('status','notfound'); end if;
  if inv.status = 'booked' then return jsonb_build_object('status','already_booked'); end if;
  if inv.status <> 'open' or inv.expires_at < now() then return jsonb_build_object('status','expired'); end if;
  if p_form is null or not (p_form = any(inv.forms)) then return jsonb_build_object('status','invalid_form'); end if;

  s_ts := p_slot::timestamp; s_date := s_ts::date; s_time := s_ts::time;
  select value into cfg from public.app_config where key = 'jsr_interview_hours_v1';
  v_start := coalesce((cfg->>'start')::time, time '09:00');
  v_end   := coalesce((cfg->>'end')::time,   time '18:00');
  v_slot  := coalesce((cfg->>'slot_min')::int, 30);
  v_win   := coalesce((cfg->>'window_days')::int, 10);
  v_lead  := coalesce((cfg->>'lead_hours')::int, 1);
  v_today := (now() at time zone 'Europe/Berlin')::date;

  -- Rahmen pruefen: Werktag, im Fenster, in der Buerozeit, nicht in der Vergangenheit.
  if extract(isodow from s_date) not between 1 and 5
     or s_date < v_today or s_date > v_today + (v_win-1)
     or s_time < v_start or (s_time + (v_slot||' minutes')::interval)::time > v_end
     or (s_ts at time zone 'Europe/Berlin') <= now() + (v_lead || ' hours')::interval then
    return jsonb_build_object('status','invalid_slot');
  end if;

  -- Kollisionsschutz: pro Slot-Zeit serialisieren, dann Belegung ATOMAR erneut pruefen.
  perform pg_advisory_xact_lock(hashtext('interview_slot'), hashtext(p_slot));
  if exists (
    select 1 from public.interview_busy_blocks(inv.participant_ids, s_date, s_date) b
    where b.start_time < (s_time + (v_slot||' minutes')::interval)::time and b.end_time > s_time
  ) then
    return jsonb_build_object('status','taken');   -- inzwischen belegt -> Frontend laedt Slots neu
  end if;

  select nullif(trim(coalesce(first_name,'')||' '||coalesce(last_name,'')),'') into v_name from public.cvs where id = inv.cv_id;

  insert into public.calendar_events(title, description, kind, start_date, start_time, end_time, recurrence,
                                     participants, created_by, created_by_name, important)
  values ('Vorstellungsgespraech mit ' || coalesce(v_name,'Bewerber'),
          'Form: ' || case p_form when 'phone' then 'Telefon' when 'teams' then 'Teams' when 'office' then 'Persoenlich im Buero' else p_form end,
          'manual', s_date, s_time, (s_time + (v_slot||' minutes')::interval)::time, 'none',
          inv.participant_ids, inv.created_by, 'Terminvereinbarung', false)
  returning id into ev_id;

  update public.interview_invites
     set status='booked', booked_slot = s_ts, booked_form = p_form, calendar_event_ids = array[ev_id]
   where id = inv.id;

  -- CV-Phase auf 'invited' (nur aus fruehen Phasen, keine Ruecksetzung aus interview/selection/contract).
  update public.cvs set status='invited', status_changed_at = now()
   where id = inv.cv_id and status in ('cv_inbound','cv_accepted','cv_confirmed','invited');

  return jsonb_build_object('status','confirmed','slot',to_char(s_ts,'YYYY-MM-DD"T"HH24:MI'),'form',p_form);
end $$;


ALTER FUNCTION "public"."confirm_interview_slot"("p_token" "text", "p_slot" "text", "p_form" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_cv_enrich_invite"("p_cv_id" "uuid", "p_form_id" "uuid" DEFAULT NULL::"uuid", "p_reusable" boolean DEFAULT false) RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_token text;
begin
  insert into cv_enrich_invites(cv_id, created_by, form_id, reusable)
    values (p_cv_id, auth.uid(), p_form_id, p_reusable)
    returning token into v_token;
  return v_token;
end $$;


ALTER FUNCTION "public"."create_cv_enrich_invite"("p_cv_id" "uuid", "p_form_id" "uuid", "p_reusable" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_interview_invite"("p_cv_id" "uuid", "p_participant_ids" "uuid"[], "p_forms" "text"[]) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_token text; v_days int;
begin
  if not (public.is_admin() or public.is_planner()) then
    raise exception 'not authorized';
  end if;
  if not exists (select 1 from public.cvs where id = p_cv_id) then
    raise exception 'cv not found';
  end if;
  if p_participant_ids is null or array_length(p_participant_ids,1) is null then
    raise exception 'participants required';
  end if;
  if p_forms is null or array_length(p_forms,1) is null or exists (
       select 1 from unnest(p_forms) f where f not in ('phone','teams','office')) then
    raise exception 'invalid forms';
  end if;
  v_days := coalesce((select (value->>'window_days')::int from public.app_config where key='jsr_interview_hours_v1'), 10);
  v_token := replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','');
  insert into public.interview_invites(cv_id, token, participant_ids, forms, status, expires_at, created_by)
  values (p_cv_id, v_token, p_participant_ids, p_forms, 'open', now() + (v_days || ' days')::interval, auth.uid());
  return jsonb_build_object('token', v_token);
end $$;


ALTER FUNCTION "public"."create_interview_invite"("p_cv_id" "uuid", "p_participant_ids" "uuid"[], "p_forms" "text"[]) OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cvs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "first_name" "text",
    "last_name" "text",
    "email" "text",
    "phone" "text",
    "city" "text",
    "status" "text" DEFAULT 'cv_inbound'::"text" NOT NULL,
    "project_id" "text",
    "target_role" "text",
    "source" "text",
    "cv_date" "date",
    "age" integer,
    "gender" "text",
    "dialect" "text",
    "education" "text",
    "education_level" "text",
    "experience_years" integer,
    "work_history" "text",
    "language_level" "text",
    "writing_level" "text",
    "languages_str" "text",
    "homeoffice_pref" "text",
    "available_from" "date",
    "dream" "text",
    "hobbies" "text",
    "travel_wish" "text",
    "photo_url" "text",
    "photo_color" "text",
    "better_email" boolean,
    "better_phone" boolean,
    "notes" "text",
    "is_structured" boolean,
    "sales_potential" boolean,
    "test_answers" "jsonb" DEFAULT '{}'::"jsonb",
    "test_scores" "jsonb" DEFAULT '{}'::"jsonb",
    "audios" "jsonb" DEFAULT '[]'::"jsonb",
    "videos" "jsonb" DEFAULT '[]'::"jsonb",
    "ai_reasoning" "jsonb" DEFAULT '{}'::"jsonb",
    "extra" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "favorite_food" "text",
    "birthday" "date",
    "primary_skill" "text",
    "id_number" "text",
    "bank_name" "text",
    "bank_account" "text",
    "assessed_level" "text",
    "hr_rating" "text",
    "contract" "jsonb",
    "status_changed_at" timestamp with time zone,
    "public_code" "text",
    "street" "text",
    "postal_code" "text",
    "country" "text",
    CONSTRAINT "cvs_status_valid" CHECK (("status" = ANY (ARRAY['cv_inbound'::"text", 'cv_accepted'::"text", 'cv_confirmed'::"text", 'invited'::"text", 'interview'::"text", 'selection1'::"text", 'selection2'::"text", 'selected'::"text", 'contract'::"text", 'training_planned'::"text", 'training'::"text", 'active'::"text", 'inactive'::"text", 'parking'::"text", 'rejected_by_us'::"text", 'rejected_by_employee'::"text", 'rejected_by_client'::"text", 'no_contact'::"text", 'homeoffice_only'::"text", 'incomplete'::"text", 'blacklist'::"text", 'already_employee'::"text", 'terminated'::"text", 'freigestellt_bezahlt'::"text", 'freigestellt_unbezahlt'::"text"])))
);


ALTER TABLE "public"."cvs" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cv_public_json"("c" "public"."cvs", "p_visible" "text"[]) RETURNS "jsonb"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select jsonb_build_object('id', c.id)
  || coalesce((
    select jsonb_object_agg(key, value)
    from jsonb_each(jsonb_build_object(
      'first_name',       c.first_name,
      'last_name',        c.last_name,
      'age',              coalesce(extract(year from age(c.birthday))::int, c.age),
      'gender',           c.gender,
      'city',             c.city,
      'dialect',          c.dialect,
      'education',        c.education,
      'education_level',  c.education_level,
      'experience_years', c.experience_years,
      'work_history',     c.work_history,
      'language_level',   c.language_level,
      'writing_level',    c.writing_level,
      'languages_str',    c.languages_str,
      'homeoffice_pref',  c.homeoffice_pref,
      'available_from',   c.available_from,
      'dream',            c.dream,
      'travel_wish',      c.travel_wish,
      'hobbies',          c.hobbies,
      'favorite_food',    c.favorite_food,
      'photo_url',        c.photo_url,
      'photo_color',      c.photo_color,
      'audios',           c.audios,
      'videos',           c.videos,
      'test_scores',      c.test_scores
    ))
    where key = any(coalesce(p_visible, '{}'::text[]))   -- HR-Auswahl nimmt nur weg
  ), '{}'::jsonb);
$$;


ALTER FUNCTION "public"."cv_public_json"("c" "public"."cvs", "p_visible" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cvs_assign_public_code"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  if new.public_code is null then new.public_code := public.gen_public_code(); end if;
  return new;
end $$;


ALTER FUNCTION "public"."cvs_assign_public_code"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cvs_guard_employee_dup"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_cph text; v_cem text; m record;
begin
  -- nur bei „frischen" Bewerbungen prüfen (kein Rückschreiben, keine bereits markierten Dubletten)
  if NEW.status is null or NEW.status not in ('cv_inbound','cv_accepted','cv_confirmed','invited') then
    return NEW;
  end if;
  v_cph := nullif(regexp_replace(coalesce(NEW.phone,''),'\D','','g'),'');
  v_cem := nullif(lower(trim(coalesce(NEW.email,''))),'');
  if v_cph is null and v_cem is null then return NEW; end if;
  select e.id, e.staff_number, trim(coalesce(e.first_name,'')||' '||coalesce(e.last_name,'')) nm, e.status,
         case when v_cem is not null and lower(trim(coalesce(e.email,'')))=v_cem then 'Mail'
              when v_cph is not null and nullif(regexp_replace(coalesce(e.phone,''),'\D','','g'),'')=v_cph then 'Telefon' end treffer
    into m
  from public.employees e
  where (v_cem is not null and lower(trim(coalesce(e.email,'')))=v_cem)
     or (v_cph is not null and nullif(regexp_replace(coalesce(e.phone,''),'\D','','g'),'')=v_cph)
  order by (case when v_cem is not null and lower(trim(coalesce(e.email,'')))=v_cem then 0 else 1 end)  -- Mail-Treffer bevorzugt
  limit 1;
  if found then
    NEW.status := 'already_employee';
    NEW.extra := coalesce(NEW.extra,'{}'::jsonb) || jsonb_build_object('employee_match',
      jsonb_build_object('employee_id', m.id, 'staff_number', m.staff_number, 'name', m.nm, 'ma_status', m.status, 'treffer', m.treffer, 'held_at', now()));
  end if;
  return NEW;
end $$;


ALTER FUNCTION "public"."cvs_guard_employee_dup"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."dm_add_member"("p_thread" "uuid", "p_emp" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare me uuid;
begin
  me := public.get_my_employee_id();
  if not exists (select 1 from public.dm_threads where id = p_thread and is_group and created_by = me)
    then raise exception 'nur der Ersteller darf Mitglieder hinzufügen'; end if;
  if not public.dm_can_chat(p_emp) then raise exception 'Kontakt nicht erlaubt'; end if;
  insert into public.dm_participants(thread_id, emp_id) values (p_thread, p_emp) on conflict do nothing;
end; $$;


ALTER FUNCTION "public"."dm_add_member"("p_thread" "uuid", "p_emp" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."dm_can_chat"("p_other" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare me uuid; me_proj text; ot_proj text;
begin
  me := public.get_my_employee_id();
  if me is null or p_other is null or me = p_other then return false; end if;
  -- Aufrufer ist externer Manager → kein Direktkanal, kann selbst niemanden anschreiben.
  if exists (
    select 1 from public.app_users au
    where au.user_id = auth.uid()
      and 'management' = any(au.role_keys)
      and coalesce(au.mgmt_external, false) = true
  ) then return false; end if;
  if public.is_admin() then return true; end if;                     -- internes management/hr
  -- Gegenüber ist Universal-Kontakt: internes Management (nicht extern) ODER HR.
  if exists (
    select 1 from public.app_users au
    where au.employee_id = p_other
      and au.active is not false
      and ( ('hr' = any(au.role_keys))
         or ('management' = any(au.role_keys) and coalesce(au.mgmt_external, false) = false) )
  ) then return true; end if;
  -- sonst: gleiches Projekt
  select project_id::text into me_proj from public.employees where id = me;
  select project_id::text into ot_proj from public.employees where id = p_other;
  return me_proj is not null and me_proj = ot_proj;
end; $$;


ALTER FUNCTION "public"."dm_can_chat"("p_other" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."dm_create_group"("p_name" "text", "p_members" "uuid"[]) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare me uuid; tid uuid; m uuid;
begin
  me := public.get_my_employee_id();
  if me is null then raise exception 'keine employee-Identität'; end if;
  insert into public.dm_threads(is_group, name, created_by)
    values (true, coalesce(nullif(trim(p_name), ''), 'Gruppe'), me) returning id into tid;
  insert into public.dm_participants(thread_id, emp_id) values (tid, me) on conflict do nothing;
  foreach m in array coalesce(p_members, '{}'::uuid[]) loop
    if m is not null and m <> me and public.dm_can_chat(m) then
      insert into public.dm_participants(thread_id, emp_id) values (tid, m) on conflict do nothing;
    end if;
  end loop;
  return tid;
end; $$;


ALTER FUNCTION "public"."dm_create_group"("p_name" "text", "p_members" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."dm_is_member"("p_thread" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1 from public.dm_participants
    where thread_id = p_thread and emp_id = public.get_my_employee_id()
  );
$$;


ALTER FUNCTION "public"."dm_is_member"("p_thread" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."dm_join_group"("p_thread" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare me uuid; ok boolean;
begin
  me := public.get_my_employee_id();
  if me is null then raise exception 'keine employee-Identität'; end if;
  if not exists (select 1 from public.dm_threads where id = p_thread and is_group)
    then raise exception 'kein Gruppen-Thread'; end if;
  -- Beitritt: management/hr universal, sonst muss man mit einem Mitglied chatten dürfen
  ok := public.is_admin() or exists (
    select 1 from public.dm_participants pp
    where pp.thread_id = p_thread and public.dm_can_chat(pp.emp_id));
  if not ok then raise exception 'Beitritt nicht erlaubt'; end if;
  insert into public.dm_participants(thread_id, emp_id) values (p_thread, me) on conflict do nothing;
end; $$;


ALTER FUNCTION "public"."dm_join_group"("p_thread" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."dm_leave_group"("p_thread" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare me uuid; n int;
begin
  me := public.get_my_employee_id();
  if me is null then raise exception 'keine employee-Identität'; end if;
  delete from public.dm_participants where thread_id = p_thread and emp_id = me;
  select count(*) into n from public.dm_participants where thread_id = p_thread;
  if n = 0 then delete from public.dm_threads where id = p_thread; end if;
end; $$;


ALTER FUNCTION "public"."dm_leave_group"("p_thread" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."dm_remove_member"("p_thread" "uuid", "p_emp" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare me uuid;
begin
  me := public.get_my_employee_id();
  if p_emp = me then raise exception 'sich selbst nicht entfernen — Gruppe verlassen'; end if;
  if not exists (select 1 from public.dm_threads where id = p_thread and is_group and created_by = me)
    then raise exception 'nur der Ersteller darf Mitglieder entfernen'; end if;
  delete from public.dm_participants where thread_id = p_thread and emp_id = p_emp;
end; $$;


ALTER FUNCTION "public"."dm_remove_member"("p_thread" "uuid", "p_emp" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."dm_rename_group"("p_thread" "uuid", "p_name" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare me uuid;
begin
  me := public.get_my_employee_id();
  update public.dm_threads
     set name = coalesce(nullif(trim(p_name), ''), name)
   where id = p_thread and is_group and created_by = me;
  if not found then raise exception 'nur der Ersteller darf umbenennen'; end if;
end; $$;


ALTER FUNCTION "public"."dm_rename_group"("p_thread" "uuid", "p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."dm_set_translations"("p_msg" "uuid", "p_tr" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare me uuid;
begin
  me := public.get_my_employee_id();
  if me is null then raise exception 'keine employee-Identität'; end if;
  update public.dm_messages
     set translations = coalesce(p_tr, '{}'::jsonb)
   where id = p_msg and from_emp_id = me;   -- nur eigene Nachricht
end; $$;


ALTER FUNCTION "public"."dm_set_translations"("p_msg" "uuid", "p_tr" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."dm_start_thread"("p_other" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare me uuid; k text; tid uuid;
begin
  me := public.get_my_employee_id();
  if me is null then raise exception 'keine employee-Identität'; end if;
  if not public.dm_can_chat(p_other) then raise exception 'Chat mit diesem Kontakt nicht erlaubt'; end if;
  k := least(me::text, p_other::text) || '_' || greatest(me::text, p_other::text);
  select id into tid from public.dm_threads where dm_key = k;
  if tid is not null then return tid; end if;
  insert into public.dm_threads(is_group, dm_key, created_by) values (false, k, me) returning id into tid;
  insert into public.dm_participants(thread_id, emp_id) values (tid, me), (tid, p_other)
    on conflict do nothing;
  return tid;
end; $$;


ALTER FUNCTION "public"."dm_start_thread"("p_other" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."dm_touch_thread"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  update public.dm_threads set updated_at = now() where id = new.thread_id;
  return new;
end; $$;


ALTER FUNCTION "public"."dm_touch_thread"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_last_admin"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  perform pg_advisory_xact_lock(hashtext('app_users_last_admin'));   -- serialisiert konkurrierende Admin-Änderungen
  if (select count(*) from public.app_users
        where active = true
          and role_keys && array['management','hr']) = 0 then
    raise exception 'Mindestens ein aktiver Admin (management/hr) muss bestehen bleiben';
  end if;
  return null;
end;
$$;


ALTER FUNCTION "public"."enforce_last_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."gen_public_code"() RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
declare c text;
begin
  loop
    c := lpad((floor(random()*900000)+100000)::int::text, 6, '0');
    exit when not exists (select 1 from public.cvs where public_code = c);
  end loop;
  return c;
end $$;


ALTER FUNCTION "public"."gen_public_code"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_interview_slots"("p_token" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  inv public.interview_invites%rowtype;
  v_name text; cfg jsonb;
  v_start time; v_end time; v_slot int; v_win int; v_lead int; v_today date;
  slots jsonb;
begin
  select * into inv from public.interview_invites where token = p_token;
  if not found then return jsonb_build_object('status','notfound'); end if;
  select nullif(trim(coalesce(first_name,'')||' '||coalesce(last_name,'')),'') into v_name from public.cvs where id = inv.cv_id;
  if inv.status = 'booked' then
    return jsonb_build_object('status','booked','applicant_name',v_name,'booked_slot',to_char(inv.booked_slot,'YYYY-MM-DD"T"HH24:MI'),'booked_form',inv.booked_form);
  end if;
  if inv.status <> 'open' or inv.expires_at < now() then
    return jsonb_build_object('status','expired','applicant_name',v_name);
  end if;
  select value into cfg from public.app_config where key = 'jsr_interview_hours_v1';
  v_start := coalesce((cfg->>'start')::time, time '09:00');
  v_end   := coalesce((cfg->>'end')::time,   time '18:00');
  v_slot  := coalesce((cfg->>'slot_min')::int, 30);
  v_win   := coalesce((cfg->>'window_days')::int, 10);
  v_lead  := coalesce((cfg->>'lead_hours')::int, 1);
  v_today := (now() at time zone 'Europe/Berlin')::date;

  with days as (
    select d::date dd
    from generate_series(v_today::timestamp, (v_today + (v_win-1))::timestamp, interval '1 day') d
    where extract(isodow from d) between 1 and 5
  ),
  times as (
    select (v_start + (n || ' minutes')::interval)::time tt
    from generate_series(0, (extract(epoch from (v_end - v_start))/60)::int - v_slot, v_slot) n
  ),
  cand as ( select dd, tt, (dd + tt) as slot_ts from days cross join times ),
  busy as ( select busy_date, start_time, end_time from public.interview_busy_blocks(inv.participant_ids, v_today, v_today + (v_win-1)) ),
  free as (
    select c.slot_ts
    from cand c
    where (c.slot_ts at time zone 'Europe/Berlin') > now() + (v_lead || ' hours')::interval
      and not exists (
        select 1 from busy b
        where b.busy_date = c.dd
          and b.start_time < (c.tt + (v_slot || ' minutes')::interval)::time
          and b.end_time   > c.tt
      )
    order by c.slot_ts
  )
  select coalesce(jsonb_agg(to_char(slot_ts,'YYYY-MM-DD"T"HH24:MI')), '[]'::jsonb) into slots from free;

  return jsonb_build_object('status','open','applicant_name',v_name,'forms',to_jsonb(inv.forms),
                            'expires_at',to_char(inv.expires_at,'YYYY-MM-DD"T"HH24:MI'),'slots',slots);
end $$;


ALTER FUNCTION "public"."get_interview_slots"("p_token" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_client_project_id"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT ca.project_id
  FROM app_users au
  JOIN client_accounts ca ON ca.id = au.client_id
  WHERE au.user_id = auth.uid()
  LIMIT 1;
$$;


ALTER FUNCTION "public"."get_my_client_project_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_employee_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(
    (select employee_id from public.app_users where user_id = auth.uid()),
    (select e.id from public.employees e
       join public.app_users au on au.user_id = auth.uid()
       where au.staff_number is not null and e.staff_number = au.staff_number
       limit 1)
  );
$$;


ALTER FUNCTION "public"."get_my_employee_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_employee_project_id"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT e.project_id
  FROM employees e
  JOIN app_users au ON au.employee_id = e.id
  WHERE au.user_id = auth.uid()
  LIMIT 1;
$$;


ALTER FUNCTION "public"."get_my_employee_project_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_project_id"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT e.project_id
  FROM employees e
  JOIN app_users au ON au.employee_id = e.id
  WHERE au.user_id = auth.uid()
  LIMIT 1;
$$;


ALTER FUNCTION "public"."get_my_project_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_role_keys"() RETURNS "text"[]
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(role_keys, '{}'::text[]) from public.app_users where user_id = auth.uid();
$$;


ALTER FUNCTION "public"."get_my_role_keys"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_public_presentation"("p_token" "text") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select jsonb_build_object(
    'id', p.id, 'title', p.title, 'project_id', p.project_id, 'skill', p.skill,
    'period_type', p.period_type, 'period_year', p.period_year, 'period_no', p.period_no,
    'data', p.data,
    'orientation', coalesce(t.orientation,'landscape'),
    'layout_key',  coalesce(t.layout_key,'default'),
    'created_at', p.created_at
  )
  from public.presentations p
  left join public.presentation_templates t on t.id = p.template_id
  where p.public_token = p_token and p.published = true
    and (p.expires_at is null or p.expires_at > now())
  limit 1;
$$;


ALTER FUNCTION "public"."get_public_presentation"("p_token" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_showcase"("p_token" "text") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select case when s.id is null then null else jsonb_build_object(
    'project_id', s.project_id,
    'title',      s.title,
    'note',       s.note,
    'created_at', s.created_at,
    'candidates', coalesce((
      select jsonb_agg(public.cv_public_json(c, s.visible_fields))
      from public.cvs c where c.id = any(s.cv_ids)
    ), '[]'::jsonb)
  ) end
  from public.showcases s
  where s.token = p_token;
$$;


ALTER FUNCTION "public"."get_showcase"("p_token" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into public.app_users (user_id, must_change_pw, active)
  values (new.id, true, false)
  on conflict (user_id) do nothing;
  return new;
end $$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."insight_dispute"("p_id" bigint, "p_reason" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  update public.agent_insights set
    seen_at        = coalesce(seen_at, now()),
    disputed_at    = now(),
    dispute_reason = nullif(trim(p_reason),'')
  where id = p_id and user_id = auth.uid();
end $$;


ALTER FUNCTION "public"."insight_dispute"("p_id" bigint, "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."insight_learning"("p_days" integer DEFAULT 14) RETURNS TABLE("agent_key" "text", "type" "text", "shown" integer, "acted" integer, "dismissed" integer, "ignored" integer, "no_action_rate" numeric, "muted" boolean)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with base as (
    select ai.agent_key, public.insight_type_key(ai.okey) as type,
      (ai.acted_at is not null) as is_acted,
      (ai.dismissed_at is not null and ai.acted_at is null) as is_dismissed,
      (ai.seen_at is not null and ai.dismissed_at is null and ai.acted_at is null and ai.seen_at < now()-interval '12 hours') as is_ignored
    from public.agent_insights ai
    where ai.seen_at >= now() - (p_days || ' days')::interval
      and (auth.uid() is null or public.is_admin())
  )
  select agent_key, type,
    count(*)::int as shown,
    count(*) filter (where is_acted)::int as acted,
    count(*) filter (where is_dismissed)::int as dismissed,
    count(*) filter (where is_ignored)::int as ignored,
    round((count(*) filter (where is_dismissed or is_ignored))::numeric / greatest(count(*),1), 2) as no_action_rate,
    (count(*) >= 5 and count(*) filter (where is_acted) = 0
      and (count(*) filter (where is_dismissed or is_ignored))::numeric / greatest(count(*),1) >= 0.9) as muted
  from base group by agent_key, type;
$$;


ALTER FUNCTION "public"."insight_learning"("p_days" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."insight_mark"("p_id" bigint, "p_state" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  update public.agent_insights set
    seen_at      = coalesce(seen_at, now()),
    dismissed_at = case when p_state='dismissed' then now() else dismissed_at end,
    acted_at     = case when p_state='acted'     then now() else acted_at end
  where id = p_id and user_id = auth.uid();
end $$;


ALTER FUNCTION "public"."insight_mark"("p_id" bigint, "p_state" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."insight_muted_types"("p_days" integer DEFAULT 14) RETURNS "text"[]
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(array_agg(type), '{}') from public.insight_learning(p_days) where muted;
$$;


ALTER FUNCTION "public"."insight_muted_types"("p_days" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."insight_type_key"("p_okey" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $_$ select regexp_replace(coalesce(p_okey,''), '_[0-9a-f-]{8,}$', ''); $_$;


ALTER FUNCTION "public"."insight_type_key"("p_okey" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."interview_busy_blocks"("p_participants" "uuid"[], "p_from" "date", "p_to" "date") RETURNS TABLE("busy_date" "date", "start_time" time without time zone, "end_time" time without time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select d::date, e.start_time, e.end_time
  from generate_series(p_from::timestamp, p_to::timestamp, interval '1 day') d
  join public.calendar_events e on e.participants && p_participants
  where e.start_time is not null and e.end_time is not null
    and d::date >= e.start_date
    and (e.until_date is null or d::date <= e.until_date)
    and (
         (coalesce(e.recurrence,'none') = 'none' and d::date = e.start_date)
      or (e.recurrence = 'weekly'   and (d::date - e.start_date) % 7  = 0)
      or (e.recurrence = 'biweekly' and (d::date - e.start_date) % 14 = 0)
      or (e.recurrence = 'monthly'  and extract(day from d) = extract(day from e.start_date))
    )
    and not exists (
      select 1 from public.calendar_overrides o
      where o.event_id = e.id and o.occurrence_date = d::date and o.hidden
    );
$$;


ALTER FUNCTION "public"."interview_busy_blocks"("p_participants" "uuid"[], "p_from" "date", "p_to" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1
    from public.app_users
    where user_id = auth.uid()
      and role_keys && array['management','hr']
  );
$$;


ALTER FUNCTION "public"."is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_emp_in_my_project"("p_emp" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (select 1 from public.employees where id=p_emp and project_id=public.get_my_employee_project_id());
$$;


ALTER FUNCTION "public"."is_emp_in_my_project"("p_emp" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_finance"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (select 1 from public.app_users where user_id=auth.uid() and role_keys && array['finance']);
$$;


ALTER FUNCTION "public"."is_finance"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_hr"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (select 1 from public.app_users where user_id=auth.uid() and role_keys && array['hr']);
$$;


ALTER FUNCTION "public"."is_hr"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_lead_only"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select public.is_planner() and not (public.is_management() or public.is_hr() or public.is_finance());
$$;


ALTER FUNCTION "public"."is_lead_only"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_management"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (select 1 from public.app_users where user_id=auth.uid() and role_keys && array['management']);
$$;


ALTER FUNCTION "public"."is_management"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_mgmt_call_user"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists(select 1 from public.mgmt_call_access where user_id = auth.uid())
$$;


ALTER FUNCTION "public"."is_mgmt_call_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_planner"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1 from public.app_users
     where user_id = auth.uid()
       and active
       and role_keys && array['management','hr','teamlead','projektleiter']::text[]
  );
$$;


ALTER FUNCTION "public"."is_planner"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_protected_employee"("emp" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (select 1 from public.app_users where employee_id=emp and role_keys && array['management']);
$$;


ALTER FUNCTION "public"."is_protected_employee"("emp" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_sales_user"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists(select 1 from public.sales_access where user_id = auth.uid())
$$;


ALTER FUNCTION "public"."is_sales_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."jobfair_claim"("p_cv_id" "uuid", "p_email" "text") RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  insert into public.applicant_messages(cv_id,purpose,channel,origin,sender_key,to_address,status)
  values (p_cv_id,'jobfair','email','campaign','recruiting',p_email,'sending')
  on conflict (cv_id) where purpose='jobfair'
    do update set status='sending', to_address=excluded.to_address, error=null, sent_at=null
    where applicant_messages.status='failed'
  returning id;
$$;


ALTER FUNCTION "public"."jobfair_claim"("p_cv_id" "uuid", "p_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."kb_feedback"("p_query" "uuid", "p_helpful" boolean, "p_note" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  update public.kb_queries
     set helpful=p_helpful, feedback_note=p_note, feedback_by=auth.uid(), feedback_at=now()
   where id=p_query
     and (user_id=auth.uid() or public.perm_proj_ok(auth.uid(),'wissen',project_id));
end $$;


ALTER FUNCTION "public"."kb_feedback"("p_query" "uuid", "p_helpful" boolean, "p_note" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."kb_retrieve"("p_project" "text", "p_q" "text", "p_limit" integer DEFAULT 8) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
declare
  v_ok boolean; q tsquery; v_qx text; member_zg text[];
  v_facts jsonb; v_chunks jsonb; v_related jsonb; v_overview jsonb;
  topics text[]; zgs text[]; over_zg text[];
  FUZZ  constant real := 0.4;   -- Schwelle für Tippfehler-Ähnlichkeit (Recall-first; die KI filtert)
  ZFUZZ constant real := 0.55;  -- strengere Schwelle für Zielgebiets-/Regions-Erkennung (ein Wort)
begin
  v_ok := coalesce((public.perm(auth.uid(),'wissen')->>'visible')::boolean,false)
          and public.perm_proj_ok(auth.uid(),'wissen',p_project);
  if not v_ok then return jsonb_build_object('ok',false,'error','forbidden'); end if;

  -- ── Region in der Frage erkennen -> zugehörige Zielgebiete sammeln ──
  select coalesce(array_agg(distinct m), '{}') into member_zg from (
    select unnest(r.members) m
    from public.kb_regions r
    where r.project_id=p_project and r.status='active'
      and (
        unaccent(lower(coalesce(p_q,''))) like '%'||unaccent(lower(r.name))||'%'
        or exists (select 1 from unnest(r.aliases) a where a<>'' and unaccent(lower(coalesce(p_q,''))) like '%'||unaccent(lower(a))||'%')
        or exists (select 1 from unnest(regexp_split_to_array(unaccent(lower(coalesce(p_q,''))), '\s+')) tok
                   where length(tok) >= 4 and (
                     word_similarity(tok, unaccent(lower(r.name))) > ZFUZZ
                     or exists (select 1 from unnest(r.aliases) a where a<>'' and word_similarity(tok, unaccent(lower(a))) > ZFUZZ)
                   ))
      )
  ) mm;

  -- Erweiterte Frage: Ortsnamen der erkannten Region anhängen (nur der Ort-Teil, ohne "Land / " -> kein Rauschen).
  v_qx := coalesce(p_q,'');
  if array_length(member_zg,1) > 0 then
    v_qx := v_qx || ' ' || (select string_agg(regexp_replace(m, '^.*/\s*', ''), ' ') from unnest(member_zg) m);
  end if;

  -- ODER statt UND (ein fehlendes Wort killt den Treffer sonst). q darf null sein — Trigram/Übersicht greifen trotzdem.
  q := nullif(replace(websearch_to_tsquery('german', v_qx)::text, ' & ', ' | '), '')::tsquery;

  -- ── Register-Fakten: exakt (Wortsuche) ODER unscharf (Trigram) ──
  select coalesce(jsonb_agg(to_jsonb(x) order by x.exact desc, x.hits desc, x.rank desc, x.sim desc), '[]'::jsonb)
    into v_facts from (
    select s.* from (
      select f.id, f.topic, f.zielgebiet, f.info_type, f.label, f.value, f.qualifier,
             f.source, f.source_locator, f.valid_from, f.valid_to, d.title as source_title,
             (q is not null and to_tsvector('german',
                coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,'')||' '||coalesce(f.value,'')) @@ q) as exact,
             case when q is null then 0 else ts_rank(to_tsvector('german',
                coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,'')||' '||coalesce(f.value,'')), q) end as rank,
             public.kb_word_hits(v_qx, coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,'')||' '||coalesce(f.value,'')) as hits,
             (select coalesce(max(word_similarity(tok, unaccent(lower(
                 coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,''))))),0)
              from unnest(regexp_split_to_array(unaccent(lower(v_qx)), '\s+')) tok
              where length(tok) >= 4) as sim
      from public.kb_facts f
      left join public.kb_documents d on d.id=f.source_document_id
      where f.project_id=p_project and f.status='active'
    ) s
    where s.exact or s.sim > FUZZ
    order by s.exact desc, s.hits desc, s.rank desc, s.sim desc
    limit p_limit
  ) x;

  -- ── Dokument-Abschnitte: exakt ODER unscharf ──
  select coalesce(jsonb_agg(to_jsonb(y) order by y.exact desc, y.hits desc, y.rank desc, y.sim desc), '[]'::jsonb)
    into v_chunks from (
    select s.* from (
      select c.id, c.section, c.content, c.document_id, d.title as doc_title, d.doc_kind,
             (q is not null and c.tsv @@ q) as exact,
             case when q is null then 0 else ts_rank(c.tsv, q) end as rank,
             public.kb_word_hits(v_qx, c.content) as hits,
             (select coalesce(max(word_similarity(tok, unaccent(lower(c.content)))),0)
              from unnest(regexp_split_to_array(unaccent(lower(v_qx)), '\s+')) tok
              where length(tok) >= 4) as sim
      from public.kb_chunks c
      join public.kb_documents d on d.id=c.document_id
      where c.project_id=p_project and d.status='active'
    ) s
    where s.exact or s.sim > FUZZ
    order by s.exact desc, s.hits desc, s.rank desc, s.sim desc
    limit p_limit
  ) y;

  -- ── Zielgebiet(e) in der (erweiterten) Frage erkennen + erkannte Region-Zielgebiete dazunehmen ──
  select array_agg(z) into over_zg from (
    select f.zielgebiet z
    from public.kb_facts f
    where f.project_id=p_project and f.status='active' and coalesce(f.zielgebiet,'') <> ''
    group by f.zielgebiet
    having (
      unaccent(lower(v_qx)) like '%'||unaccent(lower(f.zielgebiet))||'%'
      or exists (select 1 from unnest(regexp_split_to_array(unaccent(lower(v_qx)), '\s+')) tok
                 where length(tok) >= 4 and word_similarity(tok, unaccent(lower(f.zielgebiet))) > ZFUZZ)
    )
  ) t;
  if array_length(member_zg,1) > 0 then
    over_zg := (select array_agg(distinct z) from unnest(coalesce(over_zg,'{}'::text[]) || member_zg) z);
  end if;

  -- ── Übersicht: alle Fakten der erkannten Zielgebiete (auch ohne Wort-Treffer) ──
  if over_zg is not null and array_length(over_zg,1) > 0 then
    select coalesce(jsonb_agg(to_jsonb(o) order by o.zielgebiet, o.topic), '[]'::jsonb) into v_overview from (
      select f.id, f.topic, f.zielgebiet, f.info_type, f.label, f.value, f.qualifier, f.source_locator,
             d.title as source_title
      from public.kb_facts f
      left join public.kb_documents d on d.id=f.source_document_id
      where f.project_id=p_project and f.status='active' and f.zielgebiet = any(over_zg)
      limit 80
    ) o;
  else
    v_overview := '[]'::jsonb;
  end if;

  -- ── Verwandte Fakten (Nachbarschaft der direkten Treffer) ──
  if q is not null then
    select array_agg(distinct topic), array_agg(distinct zielgebiet) into topics, zgs
      from public.kb_facts f
     where f.project_id=p_project and f.status='active'
       and to_tsvector('german',
             coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,'')||' '||coalesce(f.value,'')) @@ q;
  end if;

  select coalesce(jsonb_agg(to_jsonb(z)), '[]'::jsonb) into v_related from (
    select f.id, f.topic, f.zielgebiet, f.info_type, f.label, f.value, f.qualifier, f.source_locator,
           d.title as source_title
    from public.kb_facts f
    left join public.kb_documents d on d.id=f.source_document_id
    where f.project_id=p_project and f.status='active'
      and (q is null or not (to_tsvector('german',
            coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,'')||' '||coalesce(f.value,'')) @@ q))
      and (
        (f.zielgebiet is not null and f.zielgebiet = any(coalesce(zgs,array[]::text[]))) or
        (f.topic     is not null and f.topic     = any(coalesce(topics,array[]::text[]))) or
        (f.zielgebiet is not null and v_qx ilike '%'||f.zielgebiet||'%') or
        (f.topic     is not null and v_qx ilike '%'||f.topic||'%')
      )
    limit 12
  ) z;

  return jsonb_build_object('ok',true,'facts',v_facts,'chunks',v_chunks,'related',v_related,
                            'overview',v_overview,'overview_zg',coalesce(to_jsonb(over_zg),'[]'::jsonb));
end $$;


ALTER FUNCTION "public"."kb_retrieve"("p_project" "text", "p_q" "text", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."kb_word_hits"("p_q" "text", "p_text" "text") RETURNS integer
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO 'public'
    AS $$
  select coalesce((select count(*)::int
    from unnest(regexp_split_to_array(lower(coalesce(p_q,'')), '\s+')) w
    where length(w) >= 5 and position(w in lower(coalesce(p_text,''))) > 0), 0);
$$;


ALTER FUNCTION "public"."kb_word_hits"("p_q" "text", "p_text" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."lead_state_persist"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if NEW.imported is distinct from OLD.imported
     or NEW.imported_cv_id is distinct from OLD.imported_cv_id
     or NEW.status_review is distinct from OLD.status_review then
    insert into public.lead_import_state (lead_id, imported, imported_cv_id, status_review, updated_at)
    values (NEW.id, coalesce(NEW.imported,false), NEW.imported_cv_id, NEW.status_review, now())
    on conflict (lead_id) do update
      set imported = excluded.imported, imported_cv_id = excluded.imported_cv_id,
          status_review = excluded.status_review, updated_at = now();
  end if;
  return NEW;
end $$;


ALTER FUNCTION "public"."lead_state_persist"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."lead_state_restore"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare s public.lead_import_state%rowtype;
begin
  select * into s from public.lead_import_state where lead_id = NEW.id;
  if found then
    NEW.imported       := coalesce(s.imported, false);
    NEW.imported_cv_id := s.imported_cv_id;
    NEW.status_review  := s.status_review;
  end if;
  return NEW;
end $$;


ALTER FUNCTION "public"."lead_state_restore"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."leader_situations"() RETURNS TABLE("project_id" "text", "skill" "text", "project_name" "text", "leaders" "jsonb", "situation" "jsonb")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare d date := (now() at time zone 'Europe/Berlin')::date;
        wk_start date := date_trunc('week', d)::date;
        cur_yw int := extract(isoyear from d)::int*100 + extract(week from d)::int;
begin
  return query
  with grp as (
    select e.project_id, lower(e.project_skill) as skill
    from public.employees e
    where e.position='Teamleiter' and e.project_skill is not null and e.status in ('active','training')
    group by e.project_id, lower(e.project_skill)
  ),
  team as (
    select g.project_id, g.skill, e.id as emp_id, (e.first_name||' '||e.last_name) as name, e.contract, e.absences
    from grp g join public.employees e on e.project_id=g.project_id and lower(e.project_skill)=g.skill
      and e.position in ('Agent','Senior Agent','ASP') and e.status in ('active','training')
  ),
  leaders as (
    select g.project_id, g.skill,
      jsonb_agg(jsonb_build_object('name', e.first_name||' '||e.last_name, 'user_id', au.user_id)) as leaders
    from grp g join public.employees e on e.project_id=g.project_id and lower(e.project_skill)=g.skill
      and e.position='Teamleiter' and e.status in ('active','training')
    left join public.app_users au on au.employee_id=e.id
    group by g.project_id, g.skill
  ),
  kw_pick as (
    select t.project_id, t.skill, max(ke.year*100+ke.kw) as yw
    from team t join public.kpi_entries ke on ke.emp_id=t.emp_id
    where (ke.year*100+ke.kw) <= cur_yw
    group by t.project_id, t.skill
  ),
  vals as (
    select t.project_id, t.skill, t.name, t.emp_id, kc.name as kpi, kc.id as kpi_id, ke.value, kp.yw,
      (select b->>'label' from jsonb_array_elements(kc.thresholds) b
        where ke.value >= (b->>'min')::numeric and ke.value <= (b->>'max')::numeric limit 1) as band,
      (select round(avg(ke2.value),2) from public.kpi_entries ke2
         join team t2 on t2.emp_id=ke2.emp_id and t2.project_id=t.project_id and t2.skill=t.skill
         where ke2.kpi_id=kc.id and ke2.year*100+ke2.kw = kp.yw) as team_avg,
      (select round(ke3.value,2) from public.kpi_entries ke3
         where ke3.emp_id=t.emp_id and ke3.kpi_id=kc.id and ke3.year*100+ke3.kw = kp.yw-1 limit 1) as prev,
      case when (t.contract->>'start') ~ '^\d{4}-\d{2}-\d{2}' then round((d-(t.contract->>'start')::date)/7.0)::int end as tenure_weeks,
      (select (d - max(fs.conducted_at)::date) from public.feedback_sessions fs where fs.employee_id=t.emp_id and fs.conducted_at is not null) as last_fb_days,
      (select round(wc.avg_acw_sec)    from public.weekly_calls wc where wc.employee_id=t.emp_id and wc.year*100+wc.kw=kp.yw limit 1) as acw_sec,
      (select round(wc.avg_handle_sec) from public.weekly_calls wc where wc.employee_id=t.emp_id and wc.year*100+wc.kw=kp.yw limit 1) as aht_sec,
      (select round(wc.avg_hold_sec)   from public.weekly_calls wc where wc.employee_id=t.emp_id and wc.year*100+wc.kw=kp.yw limit 1) as hold_sec
    from team t
    join public.kpi_entries ke on ke.emp_id=t.emp_id
    join public.kpi_config kc on kc.id=ke.kpi_id and lower(kc.skill)=t.skill
    join kw_pick kp on kp.project_id=t.project_id and kp.skill=t.skill and (ke.year*100+ke.kw)=kp.yw
  ),
  weak as (select v.project_id, v.skill, jsonb_agg(jsonb_build_object(
      'name',v.name,'emp_id',v.emp_id,'kpi',v.kpi,'band',v.band,'value',round(v.value,2),'prev',v.prev,'team_avg',v.team_avg,
      'tenure_weeks',v.tenure_weeks,'last_fb_days',v.last_fb_days,'acw_sec',v.acw_sec,'aht_sec',v.aht_sec,'hold_sec',v.hold_sec)) as arr
    from vals v where v.band in ('Kritisch','Schlecht') group by v.project_id, v.skill),
  strong as (select v.project_id, v.skill, jsonb_agg(jsonb_build_object('name',v.name,'emp_id',v.emp_id,'kpi',v.kpi,'band',v.band,'value',round(v.value,2),'team_avg',v.team_avg,'prev',v.prev)) as arr
    from vals v where v.band='Sehr gut' group by v.project_id, v.skill),
  kpis as (
    select q.project_id, q.skill, jsonb_agg(jsonb_build_object('kpi',q.kpi,'avg',q.team_avg,'band',q.avg_band) order by q.kpi) as arr
    from (
      select distinct v.project_id, v.skill, v.kpi, v.team_avg,
        (select b->>'label' from public.kpi_config kc, jsonb_array_elements(kc.thresholds) b
          where kc.id=v.kpi_id and v.team_avg >= (b->>'min')::numeric and v.team_avg <= (b->>'max')::numeric limit 1) as avg_band
      from vals v where v.team_avg is not null
    ) q group by q.project_id, q.skill
  ),
  absent as (select t.project_id, t.skill, jsonb_agg(distinct jsonb_build_object('name',t.name,'type',a->>'type')) as arr
    from team t, jsonb_array_elements(coalesce(t.absences,'[]'::jsonb)) a
    where (a->>'from') ~ '^\d{4}-\d{2}-\d{2}' and (a->>'from')::date <= wk_start+6
      and coalesce(nullif(a->>'to',''),(a->>'from'))::date >= wk_start
    group by t.project_id, t.skill),
  newj as (select tm.project_id, tm.skill, jsonb_agg(tm.name) as arr from team tm
    where (tm.contract->>'start') ~ '^\d{4}-\d{2}-\d{2}' and (tm.contract->>'start')::date > d-28 group by tm.project_id, tm.skill),
  nofb as (select t.project_id, t.skill, jsonb_agg(t.name) as arr from team t
    where (t.contract->>'start') ~ '^\d{4}-\d{2}-\d{2}' and (t.contract->>'start')::date <= d-28
      and not exists(select 1 from public.feedback_sessions fs where fs.employee_id=t.emp_id and fs.conducted_at is not null)
    group by t.project_id, t.skill),
  sizes as (select tm.project_id, tm.skill, count(*) as n from team tm group by tm.project_id, tm.skill)
  select g.project_id, g.skill, (select name from public.projects where id=g.project_id),
    l.leaders,
    jsonb_build_object(
      'team_size', coalesce(s.n,0),
      'absent', coalesce(ab.arr,'[]'::jsonb),
      'weak', coalesce(w.arr,'[]'::jsonb),
      'strong', coalesce(st.arr,'[]'::jsonb),
      'kpis', coalesce(kp.arr,'[]'::jsonb),
      'new_joiners', coalesce(nj.arr,'[]'::jsonb),
      'no_feedback', coalesce(nf.arr,'[]'::jsonb)
    )
  from grp g
  join leaders l on l.project_id=g.project_id and l.skill=g.skill
  left join sizes s on s.project_id=g.project_id and s.skill=g.skill
  left join absent ab on ab.project_id=g.project_id and ab.skill=g.skill
  left join weak w on w.project_id=g.project_id and w.skill=g.skill
  left join strong st on st.project_id=g.project_id and st.skill=g.skill
  left join kpis kp on kp.project_id=g.project_id and kp.skill=g.skill
  left join newj nj on nj.project_id=g.project_id and nj.skill=g.skill
  left join nofb nf on nf.project_id=g.project_id and nf.skill=g.skill;
end $$;


ALTER FUNCTION "public"."leader_situations"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."lena_scan"() RETURNS TABLE("category" "text", "severity" "text", "employee_id" "uuid", "name" "text", "label" "text", "detail" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare emp_status text[] := array['contract','training_planned','training','active','inactive','freigestellt'];
begin
  if auth.uid() is not null and not public.is_admin() then raise exception 'not authorized'; end if;
  return query
  select 'vertrag_ohne_daten','hoch', e.id, trim(coalesce(e.first_name,'')||' '||coalesce(e.last_name,'')),
         'Vertragsbeginn fehlt', coalesce(e.position,'')
  from public.employees e
  where e.status = any(emp_status) and coalesce(nullif(e.contract->>'start',''), '') = ''
  union all
  select 'ausweis_fehlt','mittel', e.id, trim(coalesce(e.first_name,'')||' '||coalesce(e.last_name,'')),
         'Ausweis-Nummer fehlt', coalesce(e.position,'')
  from public.employees e
  where e.status = any(emp_status) and coalesce(nullif(e.id_number,''), '') = ''
  union all
  select 'bank_fehlt','mittel', e.id, trim(coalesce(e.first_name,'')||' '||coalesce(e.last_name,'')),
         'Bankverbindung fehlt', coalesce(e.position,'')
  from public.employees e
  where e.status in ('training','active','inactive','freigestellt') and coalesce(nullif(e.bank->>'iban',''), '') = ''
  union all
  select 'urlaubsantrag_liegt','mittel', vr.employee_id, vr.employee_name,
         'Urlaubsantrag liegt seit '||extract(day from now()-vr.created_at)::int||' Tagen',
         to_char(vr.from_date,'DD.MM.')||'–'||to_char(vr.to_date,'DD.MM.')
  from public.vacation_requests vr
  where coalesce(vr.status,'') not in ('approved','rejected','cancelled','withdrawn')
    and vr.created_at < now() - interval '7 days'
  union all
  select 'abwesenheit_unplausibel','mittel', e.id, trim(coalesce(e.first_name,'')||' '||coalesce(e.last_name,'')),
         'Abwesenheit: Ende vor Beginn', (a->>'from')||' bis '||(a->>'to')
  from public.employees e, jsonb_array_elements(coalesce(e.absences,'[]'::jsonb)) a
  where (a->>'from') is not null and (a->>'to') is not null and (a->>'from') > (a->>'to')
  union all
  select 'portalzugang_fehlt','niedrig', e.id, trim(coalesce(e.first_name,'')||' '||coalesce(e.last_name,'')),
         'Kein aktiver Portalzugang', coalesce(e.position,'')
  from public.employees e
  where e.status in ('active','training') and not exists (
    select 1 from public.app_users au where au.employee_id = e.id and au.active)
  union all
  -- NEU: Bewerber in einer Mitarbeiter-Phase, aber (noch) kein Mitarbeiter-Datensatz — Übernahme steckengeblieben.
  select 'bewerber_ohne_ma_datensatz','hoch', c.id, trim(coalesce(c.first_name,'')||' '||coalesce(c.last_name,'')),
         'In Mitarbeiter-Phase, aber kein Mitarbeiter-Datensatz',
         'Status „'||c.status||'" — Übernahme steckengeblieben, fehlt im Team-Bereich'
  from public.cvs c
  where c.status = any(emp_status);
end $$;


ALTER FUNCTION "public"."lena_scan"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_my_showcases"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',         s.id,
    'title',      s.title,
    'note',       s.note,
    'token',      s.token,
    'created_at', s.created_at,
    'candidates', coalesce((
      select jsonb_agg(public.cv_public_json(c, s.visible_fields))
      from public.cvs c where c.id = any(s.cv_ids)
    ), '[]'::jsonb)
  ) order by s.created_at desc), '[]'::jsonb)
  from public.showcases s
  where s.project_id = public.get_my_client_project_id();
$$;


ALTER FUNCTION "public"."list_my_showcases"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_client_error"("p" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_norm text; v_sig text;
begin
  if auth.uid() is null then return; end if;   -- nur angemeldet
  v_norm := regexp_replace(coalesce(p->>'message',''), '[0-9a-fA-F]{8,}|[0-9]+', '#', 'g');
  v_sig  := md5(coalesce(p->>'kind','')||'|'||coalesce(p->>'area','')||'|'||v_norm||'|'||coalesce(p->>'source','')||':'||coalesce(p->>'lineno',''));
  insert into public.client_errors(sig,kind,message,source,lineno,colno,area,stack,sample_url,user_agent,last_user_id,last_user_name)
  values (v_sig, p->>'kind', left(p->>'message',500), left(p->>'source',300),
          nullif(p->>'lineno','')::int, nullif(p->>'colno','')::int, p->>'area', left(p->>'stack',2000),
          left(p->>'url',500), left(p->>'user_agent',300), auth.uid(), p->>'user_name')
  on conflict (sig) do update set
    count=public.client_errors.count+1, last_seen=now(),
    last_user_id=auth.uid(), last_user_name=excluded.last_user_name,
    message=excluded.message, area=excluded.area, sample_url=excluded.sample_url,
    user_agent=excluded.user_agent, stack=coalesce(excluded.stack, public.client_errors.stack),
    resolved_at=null;   -- taucht wieder auf → wieder offen
end $$;


ALTER FUNCTION "public"."log_client_error"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."lookup_pin"("p_code" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_fails  int;
  v_oldest timestamptz;
  v_pin    time_pins%rowtype;
  v_emp    employees%rowtype;
  v_sess   time_sessions%rowtype;
  v_today  date := current_date;
begin
  -- 1) Globale Rate-Limit-Sperre: >= 5 Fehlversuche in den letzten 5 Minuten?
  select count(*), min(attempted_at) into v_fails, v_oldest
    from time_pin_attempts where attempted_at > now() - interval '5 minutes';
  if v_fails >= 5 then
    return jsonb_build_object('error','locked','reason','rate_limit',
      'retry_after_seconds', greatest(1, ceil(extract(epoch from (v_oldest + interval '5 minutes' - now())))::int));
  end if;

  -- 2) PIN suchen
  select * into v_pin from time_pins where code = p_code;

  -- 2a) Optionale Pro-PIN-Sperre zuerst respektieren
  if found and v_pin.locked_until is not null and v_pin.locked_until > now() then
    return jsonb_build_object('error','locked','reason','pin_locked','until', v_pin.locked_until);
  end if;

  -- 2b) Unbekannter Code -> Fehlversuch protokollieren (+ alte Zeilen aufraeumen)
  if not found then
    delete from time_pin_attempts where attempted_at < now() - interval '1 hour';
    insert into time_pin_attempts default values;
    return jsonb_build_object('error','invalid');
  end if;

  -- 3) Mitarbeiter + Status
  select * into v_emp from employees where id = v_pin.emp_id;
  if not found then
    return jsonb_build_object('error','invalid');
  end if;
  if v_emp.status not in ('active','training') then
    return jsonb_build_object('error','inactive','status', v_emp.status);
  end if;

  -- Erfolg: Pro-PIN-Zaehler zuruecksetzen
  update time_pins set failed_attempts = 0, locked_until = null, updated_at = now()
    where emp_id = v_pin.emp_id;

  -- 4) Heutige Session (laufende bevorzugt)
  select * into v_sess from time_sessions
    where emp_id = v_pin.emp_id and session_date = v_today
    order by (clock_out is null) desc, created_at desc limit 1;

  return jsonb_build_object(
    'emp_name', trim(coalesce(v_emp.first_name,'') || ' ' || coalesce(v_emp.last_name,'')),
    'staff_number', v_emp.staff_number,
    'status', v_emp.status,
    'session', case when v_sess.id is null then null else jsonb_build_object(
      'id', v_sess.id, 'clock_in', v_sess.clock_in, 'clock_out', v_sess.clock_out,
      'pause_active', v_sess.pause_active, 'smoke_active', v_sess.smoke_active,
      'pauses', coalesce(v_sess.pauses,'[]'::jsonb), 'smokes', coalesce(v_sess.smokes,'[]'::jsonb)) end
  );
end;
$$;


ALTER FUNCTION "public"."lookup_pin"("p_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."management_activity_overview"() RETURNS TABLE("user_id" "uuid", "full_name" "text", "role_keys" "text"[], "active" boolean, "last_sign_in" timestamp with time zone, "last_seen" timestamp with time zone, "last_activity_at" timestamp with time zone, "last_activity_kind" "text", "last_activity_label" "text", "edits_30d" bigint)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_allowed text[];
begin
  if coalesce(public.perm_mode(auth.uid(),'protokoll'),'none') = 'none' then
    raise exception 'not authorized';
  end if;
  v_allowed := public.perm_allowed_projects(auth.uid(),'protokoll');   -- null = alle (Management)
  return query
  with sig as (
    select l.user_id as uid, l.created_at as at, l.entity as kind,
           coalesce(nullif(l.entity_label,''), l.entity) as label
    from public.activity_log l
    where l.action <> 'login' and l.user_id is not null
    union all
    select d.uploaded_by, d.created_at, 'upload'::text, coalesce(nullif(d.source_type,''), 'Datei')
    from public.data_imports d
    where d.uploaded_by is not null
  ),
  lastsig as ( select distinct on (uid) uid, at, kind, label from sig order by uid, at desc ),
  seenrows as (
    select uid, at from sig
    union all
    select l.user_id, l.created_at from public.activity_log l where l.action = 'login' and l.user_id is not null
  ),
  seen as ( select uid, max(at) as at from seenrows group by uid ),
  cnt as ( select uid, count(*) as n from sig where at > now() - interval '30 days' group by uid )
  select u.user_id, u.full_name, u.role_keys, u.active,
         au.last_sign_in_at,
         greatest(au.last_sign_in_at, sn.at) as last_seen,
         ls.at, ls.kind, ls.label, coalesce(c.n, 0)
  from public.app_users u
  left join auth.users au on au.id = u.user_id
  left join lastsig ls on ls.uid = u.user_id
  left join seen sn on sn.uid = u.user_id
  left join cnt c on c.uid = u.user_id
  where u.active is not false
    and u.role_keys && array['management','hr','finance','teamlead','projektleiter','qm','trainer','asp']::text[]
    and (v_allowed is null
         or exists(select 1 from public.employees e where e.id = u.employee_id and e.project_id = any(v_allowed)))
  order by ls.at asc nulls first;
end;
$$;


ALTER FUNCTION "public"."management_activity_overview"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_interview_opened"("p_token" "text") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  update public.interview_invites set opened_at = now() where token = p_token and opened_at is null;
$$;


ALTER FUNCTION "public"."mark_interview_opened"("p_token" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."match_cv_by_email"("p_email" "text") RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select id from public.cvs
  where nullif(btrim(email),'') is not null
    and lower(btrim(email)) = lower(btrim(p_email))
  order by updated_at desc nulls last
  limit 1
$$;


ALTER FUNCTION "public"."match_cv_by_email"("p_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."match_employee_by_email"("p_email" "text") RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select id from public.employees
  where nullif(btrim(coalesce(p_email,'')),'') is not null
    and ( lower(btrim(coalesce(email,'')))          = lower(btrim(p_email))
       or lower(btrim(coalesce(email_internal,''))) = lower(btrim(p_email)) )
  order by updated_at desc nulls last
  limit 1
$$;


ALTER FUNCTION "public"."match_employee_by_email"("p_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."max_checkin_scan"("p_date" "date" DEFAULT NULL::"date") RETURNS TABLE("category" "text", "subject" "text", "detail" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare d date := coalesce(p_date, ((now() at time zone 'Europe/Berlin')::date - 1));
begin
  return query
  with sched as (
    select distinct sa.project_id, sa.employee_id from public.shift_assignments sa
    where sa.work_date = d and sa.employee_id is not null
  ),
  ok as (select employee_id from public.shift_checkins where work_date = d and status in ('present','sick')),
  absent as (
    select e.id from public.employees e where exists(
      select 1 from jsonb_array_elements(coalesce(e.absences,'[]'::jsonb)) a
      where (a->>'from') ~ '^\d{4}-\d{2}-\d{2}'
        and (a->>'from')::date <= d
        and coalesce(nullif(a->>'to',''),(a->>'from'))::date >= d)
  ),
  missing as (
    select s.project_id, s.employee_id from sched s
    where s.employee_id not in (select employee_id from ok)
      and s.employee_id not in (select id from absent)
  )
  -- 1) geplant, aber nicht eingecheckt (je Projekt gebündelt, mit Namen)
  select 'nicht_eingecheckt'::text,
    (select name from public.projects where id=m.project_id)||' · '||to_char(d,'DD.MM.'),
    count(*)::text||' geplante ohne Check-in ('||string_agg((e.first_name||' '||e.last_name), ', ' order by e.first_name)
      ||') — dadurch fehlen ihre Stunden und die Anwesenheit ist unklar'
    from missing m join public.employees e on e.id=m.employee_id group by m.project_id
  union all
  -- 2) vergisst regelmäßig auszuchecken
  select 'kein_checkout', (e.first_name||' '||e.last_name),
    'vergisst regelmäßig auszuchecken ('||count(*)::text||'× in 14 Tagen) — die Arbeitszeit bleibt unvollständig'
    from public.shift_checkins sc join public.employees e on e.id=sc.employee_id
    where sc.status='present' and sc.arrival is not null and sc.departure is null and sc.work_date >= d-14
    group by sc.employee_id, e.first_name, e.last_name having count(*) >= 3
  union all
  -- 3) Teamleiter bestätigt die abgeschlossenen Check-ins seit ≥2 Tagen nicht
  select 'unbestaetigt', coalesce((select name from public.projects where id=sc.project_id), sc.project_id),
    count(*)::text||' Check-ins seit ≥2 Tagen unbestätigt — der Teamleiter hat die Anwesenheit nicht freigegeben'
    from public.shift_checkins sc
    where sc.status='present' and sc.departure is not null and sc.confirmed_at is null
      and sc.work_date <= d-2 and sc.work_date >= d-21
    group by sc.project_id having count(*) >= 1;
end $$;


ALTER FUNCTION "public"."max_checkin_scan"("p_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."max_shift_scan"("p_date" "date" DEFAULT NULL::"date") RETURNS TABLE("category" "text", "subject" "text", "detail" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare d date := coalesce(p_date, (now() at time zone 'Europe/Berlin')::date);
        nyr int := extract(isoyear from d + 7)::int;
        nkw int := extract(week    from d + 7)::int;
begin
  return query
  -- 4) eingeplant trotz Abwesenheit (nächste 14 Tage) — der wichtigste Punkt
  select 'eingeplant_abwesend'::text, (e.first_name||' '||e.last_name),
    'ist am '||to_char(sa.work_date,'DD.MM.')||' eingeplant ('||coalesce((select name from public.projects where id=sa.project_id),'?')||'), '
      ||'hat aber '||(case when ab.t='sick' then 'sich krank gemeldet' when ab.t='vacation' then 'Urlaub' when ab.t='unpaid' then 'unbezahlt frei' else 'eine Abwesenheit' end)
      ||' — die Schicht bleibt unbesetzt, das fällt sonst erst auf, wenn niemand erscheint'
    from public.shift_assignments sa join public.employees e on e.id=sa.employee_id
    cross join lateral (
      select a->>'type' as t from jsonb_array_elements(coalesce(e.absences,'[]'::jsonb)) a
      where (a->>'from') ~ '^\d{4}-\d{2}-\d{2}' and (a->>'from')::date <= sa.work_date
        and coalesce(nullif(a->>'to',''),(a->>'from'))::date >= sa.work_date limit 1) ab
    where sa.work_date between d and d + 14
  union all
  -- 1) kommende Woche ungeplant (Projekt war zuletzt aktiv)
  select 'kein_plan', (select name from public.projects where id=ap.project_id),
    'für KW '||nkw||'/'||nyr||' steht noch kein Plan — die kommende Woche ist ungeplant, es kann niemand eingeteilt werden'
    from (select distinct project_id from public.shift_assignments where work_date >= d - 28) ap
    where not exists(select 1 from public.shift_assignments sa
      where sa.project_id=ap.project_id and extract(isoyear from sa.work_date)=nyr and extract(week from sa.work_date)=nkw)
  union all
  -- 2) unbesetzt trotz Bedarf: Forecast-Stunden vorhanden, aber 0 geplant (kommende Woche)
  select 'unbesetzt', (select name from public.projects where id=rf.project_id)||' · '||rf.skill,
    'Forecast fordert '||round(rf.fc_hours)||' h für KW '||nkw||', geplant sind aber 0 — der Bedarf ist unbesetzt'
    from public.report_forecast rf
    where rf.year=nyr and rf.kw=nkw and rf.fc_hours>0
      and coalesce((select sum(sa.net_hours) from public.shift_assignments sa
        where sa.project_id=rf.project_id and sa.skill=rf.skill and extract(isoyear from sa.work_date)=nyr and extract(week from sa.work_date)=nkw),0) = 0
  union all
  -- 3) geplante Stunden weichen deutlich vom Forecast ab (>25%, geplant>0)
  select 'abweichung_forecast', (select name from public.projects where id=rf.project_id)||' · '||rf.skill,
    'geplant '||round(pl.planned)||' h vs Forecast '||round(rf.fc_hours)||' h für KW '||nkw
      ||' ('||(case when pl.planned>rf.fc_hours then '+' else '' end)||round((pl.planned-rf.fc_hours)/rf.fc_hours*100)||'%)'
      ||' — '||(case when pl.planned>rf.fc_hours then 'überplant, Kosten höher als nötig' else 'unterplant, Bedarf womöglich nicht gedeckt' end)
    from public.report_forecast rf
    cross join lateral (select coalesce(sum(sa.net_hours),0) as planned from public.shift_assignments sa
      where sa.project_id=rf.project_id and sa.skill=rf.skill and extract(isoyear from sa.work_date)=nyr and extract(week from sa.work_date)=nkw) pl
    where rf.year=nyr and rf.kw=nkw and rf.fc_hours>0 and pl.planned>0 and abs(pl.planned-rf.fc_hours)/rf.fc_hours > 0.25;
end $$;


ALTER FUNCTION "public"."max_shift_scan"("p_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."max_training_scan"("p_date" "date" DEFAULT NULL::"date") RETURNS TABLE("category" "text", "subject" "text", "detail" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare d date := coalesce(p_date, (now() at time zone 'Europe/Berlin')::date);
begin
  return query
  with plans as (
    select tp.id,
      coalesce(nullif(tp.name,''),'Schulung') as nm,
      coalesce((select p.name from public.projects p where p.id=tp.project_id),'?') as proj,
      tp.start_date,
      coalesce(tp.planned_count,0) as soll,
      coalesce(jsonb_array_length(tp.confirmed_ids),0) as ist,
      (tp.start_date - d) as dleft,
      tp.confirmed_ids
    from public.training_plans tp
    where tp.start_date is not null and tp.start_date >= d
      and (tp.active_date is null or tp.active_date > d)
      and coalesce(lower(tp.status),'') not in ('cancelled','abgesagt','storniert','done','fertig','abgeschlossen')
  )
  -- 1) unterbesetzt + Countdown (je näher der Start, desto dringlicher)
  select
    (case when pl.dleft<=3 then 'schulung_kritisch' when pl.dleft<=14 then 'schulung_knapp' else 'schulung_offen' end)::text,
    pl.nm||' · '||pl.proj,
    'startet '||(case when pl.dleft<=0 then 'heute' when pl.dleft=1 then 'morgen' else 'in '||pl.dleft||' Tagen' end)
      ||' ('||to_char(pl.start_date,'DD.MM.')||'), geplant '||pl.soll||' Plätze, zugeordnet '||pl.ist
      ||' — es fehlen noch '||(pl.soll-pl.ist)||'. '
      ||(case when pl.dleft<=3  then 'So kurz vor Start ist das kritisch: die Gruppe geht zu klein an den Start und der Bedarf bleibt ungedeckt.'
              when pl.dleft<=14 then 'Es rückt näher und wird eng — jetzt nachbesetzen, sonst startet die Gruppe unterbesetzt.'
              else 'Noch etwas Zeit, aber die Plätze sollten sich füllen.' end)
    from plans pl
    where pl.soll > 0 and pl.ist < pl.soll
  union all
  -- 2) zugeordneter Teilnehmer vor Start abgesprungen/gekündigt
  select 'schulung_abgesprungen'::text, pl.nm||' · '||pl.proj,
    (e.first_name||' '||e.last_name)||' war der Gruppe zugeordnet, ist aber '||
      (case when e.status like 'terminated%' then 'gekündigt'
            when e.status like 'rejected%'   then 'abgesprungen (abgelehnt oder zurückgezogen)'
            when e.status='blacklist'        then 'auf die Blacklist gesetzt'
            else 'nicht mehr im Prozess' end)
      ||' — die Gruppe schrumpft schon vor Start ('||to_char(pl.start_date,'DD.MM.')||'), es braucht Nachbesetzung'
    from plans pl
    cross join lateral jsonb_array_elements_text(coalesce(pl.confirmed_ids,'[]'::jsonb)) cid
    join public.employees e on e.id::text = cid
    where e.status like 'terminated%' or e.status like 'rejected%' or e.status='blacklist';
end $$;


ALTER FUNCTION "public"."max_training_scan"("p_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."max_upload_scan"() RETURNS TABLE("category" "text", "subject" "text", "detail" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare today date := (now() at time zone 'Europe/Berlin')::date;
begin
  return query
  with sched as (
    select us.project_id, us.source_type, coalesce(us.cadence,'weekly_progressive') as cadence, coalesce(us.grace_days,1) as grace
    from public.upload_schedule us where coalesce(us.active,true)
  ),
  pname as (select id, name from public.projects),
  cons as (select * from (values
      ('calls','die Anruf-Mengen'),('calls_inbound','die AHT und ACW'),('gauges','die CSAT-Werte'),
      ('rohdaten','die Arbeitsstunden'),('booking_a','die Buchungs-KPIs'),('booking_week','die Wochen-Buchungen'),
      ('booking_month','die Monats-Buchungen'),('forecast_sales','der Sales-Forecast'),('forecast_support','der Support-Forecast'),
      ('longterm','die Langzeit-Kennzahlen')
    ) c(src, folge)),
  slabel as (select * from (values
      ('calls','Call-CSV gesamt'),('calls_inbound','Call-CSV Inbound'),('gauges','Gauges'),('rohdaten','Rohdaten-Stunden'),
      ('booking_a','Booking je Agent'),('booking_week','Booking Woche'),('booking_month','Booking Monat'),
      ('forecast_sales','Forecast Sales'),('forecast_support','Forecast Support'),('longterm','Langzeit')
    ) c(src, lbl)),
  weeks as (
    select extract(isoyear from gs)::int as yr, extract(week from gs)::int as kw, (gs::date + 6) as wk_sunday
    from generate_series(date_trunc('week', today) - interval '5 weeks', date_trunc('week', today), interval '1 week') gs
  ),
  due_weekly as (   -- fällige Wochen je weekly-Quelle (Wochenende + grace vor heute)
    select s.project_id, s.source_type, w.yr, w.kw, w.wk_sunday
    from sched s cross join weeks w
    where s.cadence like 'weekly%' and (w.wk_sunday + (s.grace||' days')::interval) < today
  ),
  miss as (         -- fällig, aber kein Import
    select d.* from due_weekly d
    where not exists(select 1 from public.data_imports di
      where di.project_id=d.project_id and di.source_type=d.source_type and di.kw=d.kw and di.year=d.yr)
  ),
  latest_due as (   -- jüngste fällige Woche je Quelle
    select project_id, source_type, max(kw + yr*100) as maxkey from due_weekly group by 1,2
  )
  -- 1) ueberfaellig: jüngste fällige Woche fehlt; „seit N Wochen" = Anzahl fehlender fälliger Wochen
  select 'ueberfaellig'::text,
         (select name from pname where id=m.project_id)||' · '||coalesce((select lbl from slabel where src=m.source_type),m.source_type),
         'fehlt seit '||(select count(*) from miss m2 where m2.project_id=m.project_id and m2.source_type=m.source_type)::text
           ||' Woche(n) (zuletzt KW '||m.kw||'/'||m.yr||')'
           ||coalesce(', dadurch bleibt '||(select folge from cons where src=m.source_type)||' leer','')
    from miss m join latest_due ld on ld.project_id=m.project_id and ld.source_type=m.source_type and (m.kw+m.yr*100)=ld.maxkey
  union all
  -- 2) unvollstaendig: eine fällige Woche, in der DIESE Quelle fehlt, aber eine ANDERE derselben Woche/Projekt schon da ist
  select 'unvollstaendig',
         (select name from pname where id=m.project_id)||' · KW '||m.kw||'/'||m.yr,
         coalesce((select lbl from slabel where src=m.source_type),m.source_type)||' fehlt noch'
    from miss m
    where exists(select 1 from public.data_imports di where di.project_id=m.project_id and di.kw=m.kw and di.year=m.yr)
      and not exists(select 1 from latest_due ld where ld.project_id=m.project_id and ld.source_type=m.source_type and (m.kw+m.yr*100)=ld.maxkey)
  union all
  -- 3) wenig_zeilen: Import mit auffallend wenigen Zeilen (< 40% des Schnitts der übrigen Importe dieser Quelle/Projekt)
  select 'wenig_zeilen',
         (select name from pname where id=di.project_id)||' · '||coalesce((select lbl from slabel where src=di.source_type),di.source_type)||' KW '||di.kw||'/'||di.year,
         di.row_count||' Zeilen statt üblich ~'||round(av.avg_rows)::text
    from public.data_imports di
    join lateral (select avg(row_count) as avg_rows, count(*) as n from public.data_imports d2
                  where d2.project_id=di.project_id and d2.source_type=di.source_type and d2.id<>di.id) av on true
    where di.created_at > today - interval '6 weeks' and av.n>=2 and di.row_count is not null and av.avg_rows>0
      and di.row_count < av.avg_rows*0.4
  union all
  -- 4) muster: Quelle in ≥3 der letzten fälligen Wochen liegen geblieben
  select 'muster',
         (select name from pname where id=m.project_id)||' · '||coalesce((select lbl from slabel where src=m.source_type),m.source_type),
         'bleibt regelmäßig liegen ('||count(*)::text||' von '||(select count(*) from weeks)::text||' Wochen fehlend)'
    from miss m group by m.project_id, m.source_type having count(*)>=3;
end $$;


ALTER FUNCTION "public"."max_upload_scan"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."maya_access_scan"() RETURNS TABLE("category" "text", "subject" "text", "detail" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  valid text[] := array['start','daily_tasks','calendar','meetingnotes','agents','cockpit','wissen_system','nlquery',
    'datacheck','shiftplan','checkin','timetracking','absences','urlaubantraege','workforce','employees','orgchart',
    'performance','payroll','kanban','funnel','cvs','onboarding','bewerberlinks','dubletten','recmkt','feedback',
    'auswertung','callqa','projects','praesentation','uploads','dataimport','uploadplan','cvsync','forecast','fcist',
    'profitability','productivity','locations','spaces','training_plans','timeline','showcase','skillmatrix','elearning',
    'knowledge','languagetest','test_editor','test_preview','superadmin','cockpits','appusers','aiaccess','whosees',
    'hraccess','tabperms','activity_log','useractivity','taskadmin','mein-plan'];
  cost   text[] := array['profitability','productivity','locations','payroll'];
  adminb text[] := array['superadmin','appusers','hraccess','tabperms','aiaccess','whosees','useractivity','taskadmin'];
  locks  jsonb; grants jsonb;
begin
  select value into locks  from public.app_config where key='jsr_hr_tab_locks_v1';
  select value into grants from public.app_config where key='jsr_menu_grants_v1';
  locks  := coalesce(locks,'{}'::jsonb);
  grants := coalesce(grants,'{}'::jsonb);

  return query
  with lk as (select k as uid, v from jsonb_each(locks)  as t(k,v)),
       gr as (select k as uid, v from jsonb_each(grants) as t(k,v)),
       lk_keys as (select uid, e as key from lk, jsonb_array_elements_text(v) as e),
       gr_keys as (select uid, e as key from gr, jsonb_array_elements_text(v) as e),
       usr as (
         select a.user_id::text as uid, coalesce(u.email::text, a.full_name, a.user_id::text) as nm,
                coalesce(a.role_keys,'{}') as role_keys, coalesce(a.active,true) as active,
                greatest(
                  u.last_sign_in_at,
                  (select max(created_at) from public.activity_log  al where al.user_id = a.user_id),
                  (select max(last_seen)  from public.user_sessions se where se.user_id = a.user_id)
                ) as last_active
         from public.app_users a left join auth.users u on u.id=a.user_id
       ),
       sal as (
         select us.uid, us.nm,
           ( (us.role_keys && array['management','finance'])
             or ( exists(select 1 from gr_keys g where g.uid=us.uid and g.key='payroll')
                  and not exists(select 1 from lk_keys l where l.uid=us.uid and l.key='payroll') ) ) as menu_salary,
           coalesce((public.ai_effective_prefs(us.uid::uuid)->>'salaries') <> 'none', false) as ai_salary
         from usr us where us.active
       )
  -- 1) verwaist: Sperre/Freigabe auf nicht mehr existierenden Menüpunkt
  select 'verwaist'::text, coalesce(us.nm, l.uid), 'Sperre auf unbekannten Punkt „'||l.key||'"'
    from lk_keys l left join usr us on us.uid=l.uid where l.key <> all(valid)
  union all
  select 'verwaist', coalesce(us.nm, g.uid), 'Freigabe auf unbekannten Punkt „'||g.key||'"'
    from gr_keys g left join usr us on us.uid=g.uid where g.key <> all(valid)
  union all
  -- verwaist: Einstellungen für einen gelöschten Zugang
  select 'verwaist', d.uid, 'Menü-Einstellungen für einen nicht mehr vorhandenen Zugang'
    from (select uid from lk union select uid from gr) d
    where not exists(select 1 from usr us where us.uid=d.uid)
  union all
  -- 2) Rolle passt nicht: Kostenbereich freigegeben trotz Rolle ohne Kostenanspruch
  select 'rolle', us.nm, 'Freigabe Kostenbereich „'||g.key||'" trotz Rolle '||array_to_string(us.role_keys,'/')
    from gr_keys g join usr us on us.uid=g.uid
    where g.key = any(cost) and not (us.role_keys && array['management','finance'])
  union all
  select 'rolle', us.nm, 'Freigabe Verwaltung „'||g.key||'" trotz Rolle '||array_to_string(us.role_keys,'/')
    from gr_keys g join usr us on us.uid=g.uid
    where g.key = any(adminb) and not (us.role_keys && array['management','hr'])
  union all
  -- 3) ungenutzt + weitreichend
  select 'ungenutzt', us.nm, 'weitreichende Rechte ('||array_to_string(us.role_keys,'/')||'), zuletzt aktiv '||coalesce(to_char(us.last_active,'YYYY-MM-DD'),'nie')
    from usr us
    where us.active and (us.role_keys && array['management','hr','finance'])
      and (us.last_active is null or us.last_active < now() - interval '60 days')
  union all
  -- 4) Widerspruch Menü <-> KI (Löhne)
  select 'widerspruch', nm, 'sieht Löhne im Menü, darf sie per KI aber nicht abfragen' from sal where menu_salary and not ai_salary
  union all
  select 'widerspruch', nm, 'darf Löhne per KI abfragen, sieht sie im Menü aber nicht' from sal where ai_salary and not menu_salary;
end $$;


ALTER FUNCTION "public"."maya_access_scan"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."maya_system_scan"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare r record; cnt bigint; cur text[] := '{}'; nb jsonb;
  -- Tabellen, bei denen „leer" gesund ist (Logs/Sicherheit/optionale Protokolle) → nicht als Fund werten.
  excl text[] := array['system_findings','time_pin_attempts','dm_reads','activity_log','data_imports'];
begin
  -- 1) No-op-Importe: Status ok, aber nichts geschrieben/zugeordnet (blockierend).
  for r in select id, coalesce(nullif(btrim(file_name),''),source_type) nm, source_type, kw, created_at
             from public.data_imports
            where lower(coalesce(status,'')) in ('ok','success','done','ready','fertig')
              and coalesce(matched_count, row_count, 0) = 0 loop
    cur := cur || ('noop_import:'||r.id);
    insert into public.system_findings(fkey,category,severity,title,evidence) values(
      'noop_import:'||r.id,'no_op_import','blocking',
      'Import „'||coalesce(r.nm,'?')||'" meldete Erfolg, hat aber nichts geschrieben',
      jsonb_build_object('was',coalesce(r.nm,'?')||' ('||coalesce(r.source_type,'?')||', KW '||coalesce(r.kw::text,'?')||')',
                         'seit',r.created_at::date,'haengt_dran','die daraus gespeisten Auswertungen bleiben leer'))
    on conflict(fkey) do update set last_seen=now(), resolved_at=null;
  end loop;

  -- 2) Einstellungs-Widerspruch: derselbe Menüpunkt für einen Nutzer zugleich gesperrt UND freigegeben.
  for r in
    with locks  as (select key u, value v from jsonb_each(coalesce((select value from public.app_config where key='jsr_hr_tab_locks_v1'),'{}'::jsonb))),
         grants as (select key u, value v from jsonb_each(coalesce((select value from public.app_config where key='jsr_menu_grants_v1'),'{}'::jsonb)))
    select l.u as uid, t.tab
    from locks l join grants g on g.u=l.u
    cross join lateral (
      select x.tab from jsonb_array_elements_text(l.v) x(tab)
      intersect
      select y.tab from jsonb_array_elements_text(g.v) y(tab)
    ) t loop
    cur := cur || ('conflict_tab:'||r.uid||':'||r.tab);
    insert into public.system_findings(fkey,category,severity,title,evidence) values(
      'conflict_tab:'||r.uid||':'||r.tab,'config_conflict','cosmetic',
      'Menüpunkt „'||r.tab||'" ist für einen Nutzer gleichzeitig gesperrt und freigegeben',
      jsonb_build_object('was','Tab '||r.tab||' bei Nutzer '||r.uid,
                         'haengt_dran','die Freigabe gewinnt, die Sperre ist wirkungslos, das ist verwirrend'))
    on conflict(fkey) do update set last_seen=now(), resolved_at=null;
  end loop;

  -- 3) Leere Tabellen (ECHTE Zählung, pg_stat ist hier veraltet). Cosmetic; erst über Persistenz im Digest.
  for r in select tablename from pg_tables where schemaname='public' and tablename <> all(excl) loop
    execute format('select count(*) from public.%I', r.tablename) into cnt;
    if cnt = 0 then
      cur := cur || ('empty_table:'||r.tablename);
      insert into public.system_findings(fkey,category,severity,title,evidence) values(
        'empty_table:'||r.tablename,'empty_table','cosmetic',
        'Tabelle „'||r.tablename||'" ist leer, es wird nichts hineingeschrieben',
        jsonb_build_object('was','public.'||r.tablename,
                           'haengt_dran','wird derzeit von niemandem befüllt, evtl. tot oder ungenutzt'))
      on conflict(fkey) do update set last_seen=now(), resolved_at=null;
    end if;
  end loop;

  -- Erledigt: offene Funde, deren Bedingung nicht mehr auftritt (keine Wiederholung von Behobenem).
  update public.system_findings set resolved_at=now()
   where resolved_at is null and not (fkey = any(cur));

  -- Neue blockierende Funde (noch nicht per Slack gemeldet) für den Sofort-Kanal zurückgeben.
  select coalesce(jsonb_agg(jsonb_build_object('fkey',fkey,'title',title,'evidence',evidence) order by first_seen),'[]'::jsonb)
    into nb from public.system_findings
   where severity='blocking' and resolved_at is null and notified_at is null;
  return jsonb_build_object('scanned',coalesce(array_length(cur,1),0),'new_blocking',nb);
end $$;


ALTER FUNCTION "public"."maya_system_scan"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mgmt_task_out_guard"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.is_mgmt_call_user() then
    new.text          := old.text;
    new.context       := old.context;
    new.due_date      := old.due_date;
    new.item_id       := old.item_id;
    new.assignee_user := old.assignee_user;
    new.created_by    := old.created_by;
    new.created_by_name := old.created_by_name;
    new.created_at    := old.created_at;
  end if;
  -- Erledigt-Stempel automatisch führen.
  if new.status = 'done' and coalesce(old.status,'') <> 'done' then
    new.done_at := now(); new.done_by := auth.uid();
  elsif new.status <> 'done' then
    new.done_at := null; new.done_by := null;
  end if;
  new.updated_at := now();
  return new;
end $$;


ALTER FUNCTION "public"."mgmt_task_out_guard"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mgmt_task_out_sync"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if new.item_id is null then return new; end if;
  if new.status = 'done' and coalesce(old.status,'') <> 'done' then
    update public.mgmt_call_items set status='done', done_at=now(), updated_at=now() where id=new.item_id;
  elsif new.status <> 'done' and old.status = 'done' then
    update public.mgmt_call_items set status='open', done_at=null, updated_at=now() where id=new.item_id and status='done';
  end if;
  return new;
end $$;


ALTER FUNCTION "public"."mgmt_task_out_sync"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mn_can_read"("p_project_id" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select public.mn_can_write(p_project_id) or public.mn_is_overhead_on_project(p_project_id);
$$;


ALTER FUNCTION "public"."mn_can_read"("p_project_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mn_can_write"("p_project_id" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select public.is_management()
     or ( exists (select 1 from public.app_users au
                  where au.user_id = auth.uid() and au.active and 'projektleiter' = any(au.role_keys))
          and public.mn_employee_on_project(p_project_id) );
$$;


ALTER FUNCTION "public"."mn_can_write"("p_project_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mn_employee_on_project"("p_project_id" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1 from public.employees e
    where e.id = public.get_my_employee_id()
      and ( e.project_id::text = p_project_id
         or exists (select 1 from jsonb_array_elements(coalesce(e.project_assignments,'[]'::jsonb)) a
                    where a->>'project_id' = p_project_id and (a->>'end_date') is null) )
  );
$$;


ALTER FUNCTION "public"."mn_employee_on_project"("p_project_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mn_is_overhead_on_project"("p_project_id" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1 from public.employees e
    where e.id = public.get_my_employee_id()
      and e.position in ('Teamleiter','Trainer','QM','Projektleiter')
      and ( e.project_id::text = p_project_id
         or exists (select 1 from jsonb_array_elements(coalesce(e.project_assignments,'[]'::jsonb)) a
                    where a->>'project_id' = p_project_id and (a->>'end_date') is null) )
  );
$$;


ALTER FUNCTION "public"."mn_is_overhead_on_project"("p_project_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."my_employee_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select public.get_my_employee_id()
$$;


ALTER FUNCTION "public"."my_employee_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."my_permissions"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(jsonb_object_agg(a.key, public.perm(auth.uid(), a.key)), '{}'::jsonb)
  from public.permission_areas a;
$$;


ALTER FUNCTION "public"."my_permissions"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."nlquery_exec"("p_sql" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'ai_scoped'
    AS $_$
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
end $_$;


ALTER FUNCTION "public"."nlquery_exec"("p_sql" "text") OWNER TO "nlquery_ro";


CREATE OR REPLACE FUNCTION "public"."paul_forecast_scan"("p_date" "date" DEFAULT NULL::"date") RETURNS TABLE("category" "text", "subject" "text", "detail" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare d date := coalesce(p_date, (now() at time zone 'Europe/Berlin')::date);
begin
  return query
  with wk as (
    select gs::date as monday, extract(isoyear from gs)::int as yr, extract(week from gs)::int as kw,
           row_number() over (order by gs) as pos    -- 1=ältest … 8=jüngst
    from generate_series(date_trunc('week', d) - interval '8 weeks', date_trunc('week', d) - interval '1 week', interval '1 week') gs
  ),
  fc as (select rf.project_id, lower(rf.skill) as skill, rf.year, rf.kw, sum(rf.fc_hours) as fc
          from public.report_forecast rf group by 1,2,3,4),
  ist as (select wh.project_id, lower(wh.skill) as skill, wh.year, wh.kw, sum(wh.hours) as ist
          from public.weekly_hours wh group by 1,2,3,4),
  cmp as (
    select f.project_id, f.skill, w.kw, w.pos, f.fc, i.ist,
           case when f.fc>0 and i.ist is not null then (i.ist - f.fc)/f.fc*100 end as dev
    from wk w join fc f on f.year=w.yr and f.kw=w.kw
    left join ist i on i.project_id=f.project_id and i.skill=f.skill and i.year=w.yr and i.kw=w.kw
    where f.fc>0
  ),
  agg as (
    select project_id, skill,
      count(*) filter (where dev is not null) as n_data,
      count(*) filter (where pos>=5 and dev is not null) as n_recent,
      count(*) filter (where pos>=5 and dev <= -10) as n_unter,
      count(*) filter (where pos>=5 and dev >=  10) as n_ueber,
      avg(dev) filter (where pos>=5 and dev <= -10) as avg_unter,
      avg(dev) filter (where pos>=5 and dev >=  10) as avg_ueber
    from cmp group by project_id, skill
  ),
  latest as (
    select distinct on (project_id, skill) project_id, skill, kw, fc, ist, dev
    from cmp where dev is not null order by project_id, skill, pos desc
  ),
  pn as (select id, name from public.projects)
  -- 1) Trend Unterdeckung (>=3 der letzten 4 Wochen, je >=10% unter Plan)
  select 'fc_unterdeckung_trend'::text,
    coalesce((select name from pn where id=a.project_id),'?')||' · '||a.skill,
    'liefert seit '||a.n_unter||' der letzten Wochen unter Forecast (Ø '||round(abs(a.avg_unter))||'% Lücke) — '
      ||'kein Ausreißer, sondern anhaltende Unterdeckung: strukturell zu wenig Kapazität eingeplant, '
      ||'das kostet dauerhaft Servicelevel. Konfidenz: hoch, mehrere Wochen in Folge.'
    from agg a where a.n_unter >= 3
  union all
  -- 2) Trend Überdeckung
  select 'fc_ueberdeckung_trend'::text,
    coalesce((select name from pn where id=a.project_id),'?')||' · '||a.skill,
    'liegt seit '||a.n_ueber||' der letzten Wochen über Forecast (Ø '||round(a.avg_ueber)||'% Überhang) — '
      ||(case when a.avg_ueber>=80 then 'die Abweichung ist so groß und so beständig, dass eher Verschiedenes gemessen wird als echte Überdeckung (Skill-Zuordnung, Pausen, Stunden-Definition prüfen). Konfidenz: niedrig.'
              else 'anhaltend mehr Kapazität als geplant, die Kosten laufen über Plan. Konfidenz: hoch, mehrere Wochen in Folge.' end)
    from agg a where a.n_ueber >= 3
  union all
  -- 3) Einmalig (jüngste Woche, |dev|>=15%), sofern kein Trend gleicher Richtung läuft
  select
    (case when l.dev<0 then 'fc_unterdeckung' else 'fc_ueberdeckung' end)::text,
    coalesce((select name from pn where id=l.project_id),'?')||' · '||l.skill,
    'Ist '||round(l.ist)||' h gegen Forecast '||round(l.fc)||' h in KW '||l.kw||', '
      ||round(abs(l.dev))||'% '||(case when l.dev<0 then 'unter' else 'über' end)||' Plan'
      ||(case when l.dev>=100 then ', mehr als das Doppelte' else '' end)||' — '
      ||(case
          when l.dev<0 and abs(l.dev)>=80 then 'so wenig, dass eher eine Messlücke als echte Unterdeckung vorliegt (fehlt ein Stunden-Import? falscher Skill?). Konfidenz: niedrig.'
          when l.dev<0 then 'wir liefern die zugesagte Kapazität nicht, das gefährdet Servicelevel und Umsatz. '||(case when a.n_data<=2 then 'Nur '||a.n_data||' Wochen mit Zahlen, entsprechend vorsichtig. Konfidenz: mittel.' else 'Datenbasis solide, die Lücke ist real. Konfidenz: hoch.' end)
          when l.dev>=80 then 'das ist entweder echte Überdeckung oder wir messen Verschiedenes — bei dieser Größe eher Letzteres (Skill-Zuordnung, Pausen, Stunden-Art abgleichen). Konfidenz: niedrig.'
          else 'wir setzen mehr Kapazität ein als geplant, die Kosten liegen über Plan. '||(case when a.n_data<=2 then 'Nur '||a.n_data||' Wochen mit Zahlen, entsprechend vorsichtig. Konfidenz: mittel.' else 'Datenbasis solide, die Abweichung ist real. Konfidenz: hoch.' end)
         end)
    from latest l join agg a on a.project_id=l.project_id and a.skill=l.skill
    where abs(l.dev) >= 15
      and not (l.dev<0 and a.n_unter>=3) and not (l.dev>=0 and a.n_ueber>=3);
end $$;


ALTER FUNCTION "public"."paul_forecast_scan"("p_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."paul_whatif"("p_project" "text", "p_min_weeks" integer DEFAULT 4, "p_min_people" integer DEFAULT 6) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_pname text; v_skills jsonb := '[]'::jsonb; v_block jsonb;
  r_skill record; v_kpi_id text; v_kpi_name text; v_unit text; v_higher boolean; v_nweeks int;
begin
  -- Gate: Management (alle Projekte) ODER Projektleiter des eigenen Projekts. Bewusst NICHT is_planner()
  -- (das schlösse Teamleiter ein). Wie die Personal-Vorschau, aber eng.
  if not ( public.is_management()
    or ( exists(select 1 from public.app_users au where au.user_id=auth.uid() and au.active
                and au.role_keys && array['projektleiter']::text[])
         and p_project = public.get_my_employee_project_id() ) ) then
    raise exception 'Nur Management oder der Projektleiter dieses Projekts.';
  end if;

  select name into v_pname from public.projects where id=p_project;
  if v_pname is null then return jsonb_build_object('error','Projekt nicht gefunden'); end if;

  for r_skill in
    select distinct skill from public.kpi_config
    where project_id=p_project and level='agent' and skill is not null and skill<>'' loop

    -- KPI-Wahl: is_primary → CR (Conversion) → beste Abdeckung. Richtung: Minuten = kleiner besser, sonst größer besser.
    select c.id, c.name, c.unit, (lower(coalesce(c.unit,'')) not like '%min%')
      into v_kpi_id, v_kpi_name, v_unit, v_higher
      from public.kpi_config c
      left join (select kpi_id, count(*) n from public.kpi_entries group by kpi_id) e on e.kpi_id=c.id
     where c.project_id=p_project and c.level='agent' and c.skill=r_skill.skill
     order by c.is_primary desc nulls last, (lower(c.name)='cr') desc, coalesce(e.n,0) desc
     limit 1;
    if v_kpi_id is null then continue; end if;

    with wk as (   -- die jüngsten bis zu 8 Wochen mit Daten für diesen KPI (Grundlage)
      select year,kw from public.kpi_entries where kpi_id=v_kpi_id group by year,kw order by year desc,kw desc limit 8
    ),
    per as (       -- je Mitarbeiter der Schnitt über das Fenster (nicht eine einzelne Woche)
      select e.emp_id, round(avg(e.value)::numeric,2) val, count(distinct e.kw) wc
      from public.kpi_entries e join wk using(year,kw)
      where e.kpi_id=v_kpi_id group by e.emp_id
    ),
    rk as (        -- Drittel: bestes zuerst (Richtung beachtet)
      select per.*, ntile(3) over (order by per.val * (case when v_higher then -1 else 1 end)) tile from per
    ),
    agg as (
      select count(*) n,
             round(avg(val),2) cur,
             round((percentile_cont(0.5) within group (order by val))::numeric,2) med,
             round(avg(val) filter (where tile=1),2) benchmark,
             round(avg(val) filter (where tile=3),2) bottom
      from rk
    ),
    scen as (
      select
        round((select avg(case when (v_higher and val>=(select benchmark from agg)) or (not v_higher and val<=(select benchmark from agg)) then val else (select benchmark from agg) end) from rk),2) new_bench,
        round((select avg(case when (v_higher and val>=(select med from agg))       or (not v_higher and val<=(select med from agg))       then val else (select med from agg)       end) from rk),2) new_med
    ),
    vol as (       -- Volumen je Woche für die konkrete Übersetzung (Sales-Calls des Skills)
      select coalesce(sum(wh.sales_calls),0)::numeric v, greatest(count(distinct (wh.year::text||'-'||wh.kw::text)),1) w
      from public.weekly_hours wh join wk using(year,kw)
      where wh.project_id=p_project and wh.skill=r_skill.skill
    )
    select jsonb_build_object(
      'skill', r_skill.skill,
      'kpi', v_kpi_name, 'unit', v_unit, 'higher_is_better', v_higher,
      'n_people', a.n,
      'weeks', jsonb_build_object('n',(select count(*) from wk),'von_kw',(select min(kw) from wk),'bis_kw',(select max(kw) from wk)),
      'current_avg', a.cur, 'median', a.med, 'benchmark', a.benchmark, 'bottom_third', a.bottom,
      'gap_top_bottom', round(abs(a.benchmark - a.bottom),2),
      'scenario_to_median',    jsonb_build_object('new_avg', s.new_med,   'delta', round(s.new_med  - a.cur,2)),
      'scenario_to_benchmark', jsonb_build_object('new_avg', s.new_bench, 'delta', round(s.new_bench - a.cur,2),
        'konkret', case when lower(coalesce(v_unit,''))='%' and (select v from vol)>0
          then jsonb_build_object('einheit','Abschlüsse/Woche',
                 'volumen_woche', round((select v from vol)/(select w from vol),0),
                 'delta_pro_woche', round((s.new_bench - a.cur)/100.0 * ((select v from vol)/(select w from vol)),1))
          else null end),
      'hebel', jsonb_build_object('schwaechstes_drittel_heben_um', round(abs(a.benchmark - a.bottom),2),
               'einheit', coalesce(v_unit,'')),
      'machbarkeit', jsonb_build_array(
        'Leistung heben braucht Zeit (Coaching, Einarbeitung), nicht kurzfristig.',
        'Kundenprojekt: Besetzungs- oder Volumenänderungen brauchen Abstimmung mit dem Kunden.'),
      'people', (select jsonb_agg(jsonb_build_object(
                    'name', nullif(btrim(coalesce(em.first_name,'')||' '||coalesce(em.last_name,'')),''),
                    'value', rk.val,
                    'gruppe', case rk.tile when 1 then 'stark' when 2 then 'mittel' else 'schwach' end,
                    'weeks', rk.wc)
                  order by rk.val * (case when v_higher then -1 else 1 end))
                 from rk join public.employees em on em.id=rk.emp_id),
      'genug_daten', (a.n>=p_min_people and (select count(*) from wk)>=p_min_weeks),
      'hinweis', case when (a.n>=p_min_people and (select count(*) from wk)>=p_min_weeks) then null
                      else 'Zu dünn für eine belastbare Aussage (mind. '||p_min_people||' Personen und '||p_min_weeks||' Wochen).' end
    )
    into v_block from agg a cross join scen s;

    if v_block is not null then v_skills := v_skills || v_block; end if;
  end loop;

  return jsonb_build_object('project_id',p_project,'project_name',v_pname,
    'grundlage','Schnitt über die letzten Wochen (Momentaufnahme, nicht eine einzelne Woche).',
    'skills',v_skills);
end $$;


ALTER FUNCTION "public"."paul_whatif"("p_project" "text", "p_min_weeks" integer, "p_min_people" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."perm"("p_uid" "uuid", "p_area" "text") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with ov as (select * from public.user_permissions where user_id=p_uid and area_key=p_area),
  rk as (select unnest(coalesce((select role_keys from public.app_users where user_id=p_uid),'{}'::text[])) as role_key),
  rd as (
    select
      bool_or(rp.visible) as visible,
      max(case rp.mode when 'edit' then 2 when 'read' then 1 else 0 end) as m,
      max(case rp.salary when 'all' then 2 when 'own' then 1 else 0 end) as sal,
      max(case rp.direction when 'up' then 2 when 'side' then 1 else 0 end) as dir,
      max(case rp.projects when 'all' then 2 when 'list' then 1 else 0 end) as prj,
      max(case rp.skill when 'all' then 1 else 0 end) as skl,
      max(case rp.columns when 'voll' then 2 when 'personal' then 1 else 0 end) as col
    from public.role_permissions rp join rk on rk.role_key=rp.role_key where rp.area_key=p_area
  )
  select case when exists(select 1 from ov)
    then (select jsonb_build_object('visible',visible,'mode',mode,'salary',salary,'direction',direction,
            'projects',projects,'project_ids',project_ids,'skill',skill,
            'columns',coalesce(columns,'operativ'),'source','user') from ov)
    else (select jsonb_build_object(
            'visible', coalesce((select visible from rd),false),
            'mode', (array['none','read','edit'])[coalesce((select m from rd),0)+1],
            'salary', (array['none','own','all'])[coalesce((select sal from rd),0)+1],
            'direction', (array['down','side','up'])[coalesce((select dir from rd),0)+1],
            'projects', (array['own','list','all'])[coalesce((select prj from rd),0)+1],
            'project_ids', '{}'::text[],
            'skill', (array['own','all'])[coalesce((select skl from rd),0)+1],
            'columns', (array['operativ','personal','voll'])[coalesce((select col from rd),0)+1],
            'source','role'))
  end;
$$;


ALTER FUNCTION "public"."perm"("p_uid" "uuid", "p_area" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."perm_allowed_projects"("p_uid" "uuid", "p_area" "text") RETURNS "text"[]
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare pr jsonb; scope text;
begin
  pr := public.perm(p_uid, p_area); scope := pr->>'projects';
  if scope = 'all' then return null; end if;                              -- alle Projekte
  if scope = 'list' then
    return coalesce((select array(select jsonb_array_elements_text(pr->'project_ids'))), '{}'::text[]);
  end if;
  -- 'own' (Default): nur das eigene Projekt
  return coalesce((select array[project_id] from public.employees where id=public.perm_caller_emp_id(p_uid) and project_id is not null), '{}'::text[]);
end $$;


ALTER FUNCTION "public"."perm_allowed_projects"("p_uid" "uuid", "p_area" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."perm_area_grant_management"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into public.role_permissions (role_key, area_key, visible, mode, salary, direction, projects, project_ids, skill, columns)
  values ('management', new.key, true, 'edit', 'all', 'up', 'all', '{}'::text[], 'all', 'voll')
  on conflict (role_key, area_key) do nothing;
  return new;
end $$;


ALTER FUNCTION "public"."perm_area_grant_management"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."perm_area_has_skill"("p_area" "text") RETURNS boolean
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
  select coalesce((select (axes->>'skill')::boolean from public.permission_areas where key=p_area), false)
$$;


ALTER FUNCTION "public"."perm_area_has_skill"("p_area" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."perm_caller_emp_id"("p_uid" "uuid" DEFAULT "auth"."uid"()) RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select employee_id from public.app_users where user_id=p_uid
$$;


ALTER FUNCTION "public"."perm_caller_emp_id"("p_uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."perm_caller_rank"("p_uid" "uuid" DEFAULT "auth"."uid"()) RETURNS integer
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(public.ai_position_rank((select position from public.employees where id=public.perm_caller_emp_id(p_uid))), 100)
$$;


ALTER FUNCTION "public"."perm_caller_rank"("p_uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."perm_caller_skills"("p_uid" "uuid" DEFAULT "auth"."uid"()) RETURNS "text"[]
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select array(select distinct s from (
    select coalesce(project_skill, skill) s from public.employees where id=public.perm_caller_emp_id(p_uid)
  ) x where s is not null)
$$;


ALTER FUNCTION "public"."perm_caller_skills"("p_uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."perm_emp_row_ok"("p_uid" "uuid", "p_area" "text", "p_emp_id" "uuid", "p_project" "text", "p_skill" "text", "p_position" "text") RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare crank int; rrank int; dir text;
begin
  if p_emp_id is not null and p_emp_id = public.perm_caller_emp_id(p_uid) then return true; end if;  -- eigene Zeile immer
  if not public.perm_proj_ok(p_uid, p_area, p_project, p_skill) then return false; end if;
  crank := public.perm_caller_rank(p_uid);
  -- Positionslose MA defensiv als hoch (verborgen) behandeln, nicht als unterste Ebene.
  rrank := case when p_position is null or p_position = '' then 999 else public.ai_position_rank(p_position) end;
  dir  := coalesce(public.perm(p_uid,p_area)->>'direction','down');
  if rrank > crank and dir <> 'up'  then return false; end if;   -- höher sehen nur bei 'up'
  if rrank = crank and dir =  'down' then return false; end if;   -- 'down' ohne gleiche Ebene
  return true;
end $$;


ALTER FUNCTION "public"."perm_emp_row_ok"("p_uid" "uuid", "p_area" "text", "p_emp_id" "uuid", "p_project" "text", "p_skill" "text", "p_position" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."perm_mode"("p_uid" "uuid", "p_area" "text") RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(public.perm(p_uid,p_area)->>'mode','none')
$$;


ALTER FUNCTION "public"."perm_mode"("p_uid" "uuid", "p_area" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."perm_overhead_ok"("p_uid" "uuid" DEFAULT "auth"."uid"()) RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists(select 1 from public.app_users
                where user_id=p_uid and active and role_keys && array['management','finance','hr']::text[])
$$;


ALTER FUNCTION "public"."perm_overhead_ok"("p_uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."perm_proj_ok"("p_uid" "uuid", "p_area" "text", "p_project" "text", "p_skill" "text" DEFAULT NULL::"text") RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare allowed text[]; cskills text[];
begin
  allowed := public.perm_allowed_projects(p_uid, p_area);
  if allowed is not null and (p_project is null or not (p_project = any(allowed))) then return false; end if;
  -- Skill-Achse nur wo der Bereich sie hat und der Aufrufer auf Teamleiter-Ebene (<=30) sitzt.
  if public.perm_area_has_skill(p_area) and public.perm_caller_rank(p_uid) <= 30 and p_skill is not null then
    cskills := public.perm_caller_skills(p_uid);
    if array_length(cskills,1) is not null and not (p_skill = any(cskills)) then return false; end if;
  end if;
  return true;
end $$;


ALTER FUNCTION "public"."perm_proj_ok"("p_uid" "uuid", "p_area" "text", "p_project" "text", "p_skill" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."perm_salary_ok"("p_uid" "uuid", "p_area" "text", "p_emp_id" "uuid" DEFAULT NULL::"uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select case (public.perm(p_uid,p_area)->>'salary')
    when 'all' then true
    when 'own' then p_emp_id is not null and p_emp_id = public.perm_caller_emp_id(p_uid)
    else false end
$$;


ALTER FUNCTION "public"."perm_salary_ok"("p_uid" "uuid", "p_area" "text", "p_emp_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."permissions_overview"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select case when not public.is_management() then '[]'::jsonb else (
    select coalesce(jsonb_agg(jsonb_build_object(
      'user_id', u.user_id, 'name', u.full_name, 'role_keys', u.role_keys,
      'areas', (select jsonb_object_agg(a.key, public.perm(u.user_id, a.key)) from public.permission_areas a)
    ) order by u.full_name), '[]'::jsonb)
    from public.app_users u
    where u.active and u.role_keys && array['management','hr','finance','teamlead','projektleiter']::text[]
  ) end;
$$;


ALTER FUNCTION "public"."permissions_overview"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."promote_employee"("p_payload" "jsonb") RETURNS "public"."employees"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
declare is_adm boolean; cols text; sel text; rec public.employees;
begin
  is_adm := public.is_management() or public.is_hr() or public.is_finance();
  if not (is_adm or (public.is_planner() and public.perm_mode(auth.uid(),'emp')='edit' and public.perm_proj_ok(auth.uid(),'emp',(p_payload->>'project_id'), null))) then
    raise exception 'Nicht berechtigt, für dieses Projekt anzulegen.';
  end if;
  -- Leads dürfen keine Gehalts-/Bankdaten setzen; ID vergibt die DB.
  if not is_adm then
    p_payload := p_payload - 'fixed_salary' - 'hourly_rate' - 'salary_currency' - 'salary_type' - 'guaranteed_pct' - 'bank' - 'id_number';
  end if;
  -- Client-generierte gültige uuid behalten (optimistisches UI passt); sonst DB-Default vergeben lassen.
  if (p_payload->>'id') is null or (p_payload->>'id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    p_payload := p_payload - 'id';
  end if;
  -- Dynamische Spaltenliste: nur vorhandene Keys, die echte employees-Spalten sind (Rest fällt weg).
  select string_agg(quote_ident(k), ','), string_agg('r.'||quote_ident(k), ',')
    into cols, sel
  from jsonb_object_keys(p_payload) as t(k)
  where exists (select 1 from information_schema.columns c
                where c.table_schema='public' and c.table_name='employees' and c.column_name=t.k);
  if cols is null then raise exception 'Leere Nutzlast.'; end if;
  execute format('insert into public.employees (%s) select %s from jsonb_populate_record(null::public.employees, $1) r returning *', cols, sel)
    into rec using p_payload;
  return rec;
end $_$;


ALTER FUNCTION "public"."promote_employee"("p_payload" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."protect_salary_on_update"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_abs jsonb;
begin
  if public.is_lead_only() and coalesce(current_setting('app.lead_employee_write', true),'') <> '1' then
    v_abs := to_jsonb(NEW)->'absences';
    NEW := OLD; NEW.absences := coalesce(v_abs, OLD.absences); NEW.updated_at := now();
    return NEW;
  end if;
  if public.is_protected_employee(NEW.id) and not (public.is_management() or public.is_finance()) then
    NEW.fixed_salary:=OLD.fixed_salary; NEW.hourly_rate:=OLD.hourly_rate; NEW.salary_currency:=OLD.salary_currency;
    NEW.bank:=OLD.bank; NEW.contract:=OLD.contract; NEW.id_number:=OLD.id_number;
  end if;
  return NEW;
end $$;


ALTER FUNCTION "public"."protect_salary_on_update"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."respond_counter"("p_request_id" "uuid", "p_accept" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_row   public.vacation_requests%rowtype;
  v_me    uuid;
  v_from  date;
  v_to    date;
  v_days  integer;
  v_exit  date;
begin
  v_me := public.get_my_employee_id();

  select * into v_row from public.vacation_requests where id = p_request_id;
  if not found then
    raise exception 'Antrag nicht gefunden';
  end if;

  -- Guard 1: nur der Mitarbeiter, dem der Antrag gehört
  if v_me is null or v_row.employee_id <> v_me then
    raise exception 'Kein Zugriff auf diesen Antrag';
  end if;

  -- Guard 2: nur aus status='counter' heraus (kein Doppel-Annehmen, kein
  --          Umbiegen von pending/approved/rejected)
  if v_row.status <> 'counter' then
    raise exception 'Antrag ist nicht im Status counter (aktuell: %)', v_row.status;
  end if;

  if p_accept then
    -- Gegenvorschlags-Daten; Fallback auf die ursprünglichen Antragsdaten
    v_from := coalesce((v_row.counter_proposal->>'from')::date, v_row.from_date);
    v_to   := coalesce((v_row.counter_proposal->>'to')::date,   v_row.to_date);

    -- Offboarding-Schnitt 1: Grenze = frühestes von Austrittsdatum und Vertragsende
    -- (least ignoriert NULL). Gesetzt und v_to danach → hart blocken (inklusiv).
    select least(e.termination_date, nullif(e.contract->>'end','')::date)
      into v_exit
      from public.employees e where e.id = v_row.employee_id;
    if v_exit is not null and v_to > v_exit then
      raise exception 'Zeitraum liegt nach dem Austritts-/Vertragsende (%)', v_exit;
    end if;

    -- Werktage (Mo–Fr) im Zeitraum — serverseitig, nicht dem Client vertrauen
    select count(*)::int into v_days
      from generate_series(v_from, v_to, interval '1 day') d
     where extract(dow from d) not in (0, 6);

    -- Absence an den Mitarbeiter schreiben (SECURITY DEFINER umgeht RLS).
    -- Keys wie das Frontend: start/end (Matcher/Workforce) + from/to (Kompat),
    -- type/days/paid; paid = (type <> 'unpaid').
    update public.employees
       set absences = coalesce(absences, '[]'::jsonb) || jsonb_build_object(
             'type',         v_row.type,
             'start',        to_char(v_from, 'YYYY-MM-DD'),
             'end',          to_char(v_to,   'YYYY-MM-DD'),
             'from',         to_char(v_from, 'YYYY-MM-DD'),
             'to',           to_char(v_to,   'YYYY-MM-DD'),
             'days',         v_days,
             'paid',         (v_row.type <> 'unpaid'),
             'approved',     true,
             'approved_by',  'MA (counter akzeptiert)',
             'from_request', p_request_id
           )
     where id = v_row.employee_id;

    -- Antrag auf approved + den vereinbarten Zeitraum festschreiben
    update public.vacation_requests
       set status = 'approved', from_date = v_from, to_date = v_to, days = v_days
     where id = p_request_id;
  else
    -- Ablehnen des Gegenvorschlags: nur Status, keine Absence
    update public.vacation_requests
       set status = 'rejected'
     where id = p_request_id;
  end if;
end;
$$;


ALTER FUNCTION "public"."respond_counter"("p_request_id" "uuid", "p_accept" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sales_can_send"("p_email" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(nullif(trim(p_email),''),'') <> ''
     and not exists(select 1 from public.sales_suppression s where s.email = lower(trim(p_email)))
$$;


ALTER FUNCTION "public"."sales_can_send"("p_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sales_email_tier"("p_email" "text") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $_$
declare lp text;
begin
  if p_email is null or position('@' in p_email)=0 then return null; end if;
  lp := lower(split_part(p_email,'@',1));
  lp := regexp_replace(lp,'\+.*$','');   -- plus-Adressierung weg
  if lp = any(array['info','kontakt','contact','office','mail','email','hello','hallo','hi','team','all','welcome','moin','zentrale','post','anfrage','anfragen','newsletter','no-reply','noreply']) then return 'general'; end if;
  if lp = any(array['vertrieb','sales','verkauf','service','support','kundenservice','kundenbetreuung','personal','hr','jobs','karriere','career','bewerbung','recruiting','marketing','presse','press','einkauf','buchhaltung','finance','accounting','it','admin','empfang','reception','beratung','betrieb']) then return 'department'; end if;
  if lp ~ '^[a-z]{2,}[._-][a-z]{2,}' then return 'personal'; end if;   -- vorname.nachname
  return 'department';                                                -- Einzelname unbekannt → vorsichtig Mitte
end $_$;


ALTER FUNCTION "public"."sales_email_tier"("p_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sales_leads_set_tier"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin new.email_tier := public.sales_email_tier(new.contact_email); return new; end $$;


ALTER FUNCTION "public"."sales_leads_set_tier"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sales_mark_dead"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare n int;
begin
  with upd as (
    update public.sales_leads set status='dead', updated_at=now()
    where status in ('contacted','opened')
      and coalesce(last_activity_at, created_at) < now() - interval '30 days'
    returning id
  )
  insert into public.sales_events(lead_id, kind, detail)
  select id, 'note', jsonb_build_object('auto','tot: 30 Tage ohne Reaktion') from upd;
  get diagnostics n = row_count;
  return n;
end $$;


ALTER FUNCTION "public"."sales_mark_dead"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sales_recompute_scores"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare r record; n int:=0;
begin
  if auth.uid() is not null and not is_sales_user() then raise exception 'kein Zugriff'; end if;
  for r in select id from sales_leads loop
    update sales_leads set score = sales_score_for(r.id) where id=r.id;
    n := n+1;
  end loop;
  return n;
end $$;


ALTER FUNCTION "public"."sales_recompute_scores"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sales_score_for"("p_lead_id" "uuid") RETURNS numeric
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare l record; cfg jsonb; ind jsonb; iw numeric:=0;
  fit numeric:=0; reach numeric:=0; research numeric:=0; s numeric;
  n_sent int; n_open int; n_reply int; sz int; smin int; smax int; ssmin int; ssmax int; gb numeric;
begin
  select * into l from sales_leads where id=p_lead_id;
  if not found then return null; end if;
  if l.status in ('won','lost','dead','suppressed') then return 0; end if;
  select value into cfg from app_config where key='jsr_sales_fit_v1';

  if cfg is not null and coalesce(l.industry,'')<>'' then
    for ind in select * from jsonb_array_elements(cfg->'industries') loop
      if position(lower(ind->>'name') in lower(l.industry))>0
         or position(lower(split_part(ind->>'name',' ',1)) in lower(l.industry))>0 then
        iw := greatest(iw, coalesce((ind->>'weight')::numeric,0));
      end if;
    end loop;
  end if;
  fit := fit + iw*2;

  sz := l.company_size;
  smin := coalesce((cfg->'size'->>'min')::int, 0);      smax := coalesce((cfg->'size'->>'max')::int, 2000000000);
  ssmin := coalesce((cfg->'size'->>'sweet_min')::int, smin); ssmax := coalesce((cfg->'size'->>'sweet_max')::int, smax);
  if sz is null then fit := fit + 4;
  elsif sz between ssmin and ssmax then fit := fit + 14;
  elsif sz between smin and smax then fit := fit + 8;
  else fit := fit + 1; end if;

  gb := coalesce((cfg->>'growth_bonus')::numeric, 0);
  if coalesce(l.growth,'')<>'' then fit := fit + gb; end if;

  select count(*) filter (where kind='sent'), count(*) filter (where kind='opened'), count(*) filter (where kind='replied')
    into n_sent, n_open, n_reply from sales_events where lead_id=p_lead_id;
  if coalesce(n_reply,0)>0 then reach := reach + 25; end if;
  reach := reach + least(coalesce(n_open,0)*4, 12);
  if coalesce(n_sent,0)>=2 and coalesce(n_open,0)=0 and coalesce(n_reply,0)=0 then
    reach := reach - least((n_sent-1)*4, 16);
  end if;

  if l.email_tier = 'personal' then reach := reach + 8;
  elsif l.email_tier = 'general' then reach := reach - 8;
  end if;

  if coalesce(l.hook,'')<>'' then
    if coalesce((l.research->>'hook_general')::boolean,false) then research := 2; else research := 6; end if;
  end if;

  s := fit + reach + research;
  if s < 0 then s := 0; end if;
  return round(s,1);
end $$;


ALTER FUNCTION "public"."sales_score_for"("p_lead_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."session_ping"("p_session_id" "text", "p_view" "text" DEFAULT NULL::"text", "p_agent" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_name text;
begin
  if auth.uid() is null then return; end if;
  select coalesce(full_name,'') into v_name from public.app_users where user_id = auth.uid();
  insert into public.user_sessions(session_id, user_id, user_name, view_key, user_agent)
    values (p_session_id, auth.uid(), v_name, p_view, p_agent)
  on conflict (session_id) do update
    set last_seen  = now(),
        ping_count = public.user_sessions.ping_count + 1,
        view_key   = coalesce(excluded.view_key, public.user_sessions.view_key);
end $$;


ALTER FUNCTION "public"."session_ping"("p_session_id" "text", "p_view" "text", "p_agent" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_employee_absences"("p_employee_id" "uuid", "p_absences" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_proj text;
begin
  select project_id into v_proj from public.employees where id = p_employee_id;
  if not found then
    raise exception 'employee not found';
  end if;
  -- Berechtigt: Admin (management/hr/finance) ODER Lead (planner) im SELBEN Projekt wie sein eigener Datensatz.
  if not (
    public.is_management() or public.is_hr() or public.is_finance()
    or (public.is_planner() and v_proj is not distinct from public.get_my_employee_project_id())
  ) then
    raise exception 'not authorized';
  end if;
  update public.employees
     set absences = coalesce(p_absences, '[]'::jsonb), updated_at = now()
   where id = p_employee_id;
end $$;


ALTER FUNCTION "public"."set_employee_absences"("p_employee_id" "uuid", "p_absences" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."spin_wheel"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_emp         uuid;
  v_today       date := current_date;
  v_month       text := to_char(current_date,'YYYY-MM');
  v_existing    wheel_spins%rowtype;
  v_special     wheel_specials%rowtype;
  v_has_special boolean := false;
  v_source      text := 'normal';
  v_special_id  uuid := null;
  v_amount      numeric := 0;
  v_budget      numeric := 0;
  v_spent       numeric := 0;
  v_rest        numeric := 0;
  v_last_win    date;
  v_weeks       int := 4;
  v_weight      numeric := 1.0;
  v_kpi_factor  numeric := 1.0;
  v_g           numeric;
  v_rand        numeric;
  v_tranche     numeric;
  v_awarded_cnt int;
  v_awarded_sum numeric;
  v_prizes      jsonb;
  v_has_pos     boolean;
  v_aff_pos     boolean;
  v_msg         text;
begin
  -- Aufrufer -> Mitarbeiter (serverseitig, kein Parameter)
  select employee_id into v_emp from app_users where user_id = auth.uid();
  if v_emp is null then
    return jsonb_build_object('amount',0,'source','none','message','Kein verknüpfter Mitarbeiter.');
  end if;

  -- 1. Tages-Check: schon heute gedreht?
  select * into v_existing from wheel_spins where emp_id = v_emp and spin_date = v_today;
  if found then
    return jsonb_build_object('amount', v_existing.amount, 'source', v_existing.source,
      'message','Heute schon gedreht — komm morgen wieder!', 'alreadySpun', true);
  end if;

  v_rand := random();   -- einmal pro Dreh

  -- 2. Sonderaktion aktiv?
  select * into v_special from wheel_specials
    where start_date <= v_today and v_today <= end_date
    order by created_at desc limit 1;
  v_has_special := found;

  if v_has_special then
    -- Fairness/KPI NUR für Sonderaktionen (unverändertes Verhalten; im Normal-Pfad bewusst nicht mehr genutzt).
    -- Fairness: Wochen seit letztem Gewinn (nie gewonnen -> Garantie-Niveau 4)
    select max(spin_date) into v_last_win from wheel_spins where emp_id = v_emp and amount > 0;
    if v_last_win is not null then
      v_weeks := greatest(0, floor((v_today - v_last_win)/7.0)::int);
    else
      v_weeks := 4;
    end if;
    -- KPI-Faktor: juengste bis 6 kpi_entries gegen kpi_config.thresholds bewerten, Tier-Guete mitteln.
    select avg(g) into v_g from (
      select (
        select (jsonb_array_length(kc.thresholds) - (t.ord - 1))::numeric
               / nullif(jsonb_array_length(kc.thresholds),0)
        from kpi_config kc
        cross join lateral (
          select ord
          from jsonb_array_elements(kc.thresholds) with ordinality as th(val, ord)
          where e.value >= (th.val->>'min')::numeric
            and e.value <= (th.val->>'max')::numeric
          order by ord limit 1
        ) t
        where kc.id = e.kpi_id
      ) as g
      from (
        select kpi_id, value from kpi_entries where emp_id = v_emp
        order by year desc nulls last, kw desc nulls last limit 6
      ) e
    ) sub;
    if v_g is not null then
      if v_g >= 0.66 then v_kpi_factor := 1.15;
      elsif v_g < 0.34 then v_kpi_factor := 0.85;
      else v_kpi_factor := 1.0; end if;
    end if;
    v_weight := (1.0 + 0.25 * v_weeks) * v_kpi_factor;
    if v_weeks >= 4 then v_weight := v_weight + 2.0; end if;   -- Garantie: deutlich erhoeht
    v_weight := greatest(0.1, v_weight);

    v_source := 'special';
    v_special_id := v_special.id;
    select count(*) filter (where amount > 0),
           coalesce(sum(amount) filter (where amount > 0),0)
      into v_awarded_cnt, v_awarded_sum
      from wheel_spins where special_id = v_special.id;
    v_rest    := coalesce(v_special.total_amount,0) - v_awarded_sum;
    v_tranche := coalesce(v_special.tranche_amount,0);
    if v_awarded_cnt >= coalesce(v_special.tranche_count,0) or v_tranche <= 0 or v_rest < v_tranche then
      v_amount := 0;   -- Tranchen/Topf ausgeschoepft
    else
      -- Fairness-Roll: 0 vs Tranche (hoeheres Gewicht -> kleineres 0-Gewicht)
      if v_rand * ((40.0 / v_weight) + 20.0) >= (40.0 / v_weight) then
        v_amount := v_tranche;
      else
        v_amount := 0;
      end if;
    end if;
  else
    -- 3. Normaler Glücksrad-Dreh: Beträge + Gewichte kommen AUSSCHLIESSLICH aus app_config.jsr_wheel_cfg.prizes.
    --    Keine versteckte Rechnung. Budget = harte Grenze (Variante 1).
    select coalesce(amount,0) into v_budget from wheel_budgets where month = v_month;
    v_budget := coalesce(v_budget,0);
    select coalesce(sum(amount),0) into v_spent from wheel_spins
      where spin_date >= date_trunc('month', v_today)::date
        and spin_date <  (date_trunc('month', v_today) + interval '1 month')::date;
    v_rest := v_budget - v_spent;

    v_prizes := coalesce((select value->'prizes' from app_config where key = 'jsr_wheel_cfg'), '[]'::jsonb);

    -- Gibt es überhaupt positive Preise? Und deckt der Resttopf mindestens einen davon voll?
    select exists(
        select 1 from jsonb_array_elements(v_prizes) p
        where coalesce((p->>'amount')::numeric,0) > 0
      ) into v_has_pos;
    select exists(
        select 1 from jsonb_array_elements(v_prizes) p
        where coalesce((p->>'amount')::numeric,0) > 0
          and coalesce((p->>'amount')::numeric,0) <= v_rest
      ) into v_aff_pos;

    if v_has_pos and not v_aff_pos then
      -- Monatstopf deckt keinen einzigen positiven Preis mehr -> ehrlich ausgeschoepft.
      v_amount := 0;
      v_source := 'budget_exhausted';
    else
      -- Gewichteter Zufall über die zulässigen Preise: alle "leider nichts" (amount=0) + alle Preise,
      -- die der Resttopf noch VOLL deckt (amount<=rest). Die in der Config gepflegten Gewichte SIND die Chancen.
      select amt into v_amount from (
        select (p->>'amount')::numeric as amt,
               sum(coalesce((p->>'weight')::numeric,1)) over (order by ord) as cum,
               sum(coalesce((p->>'weight')::numeric,1)) over () as total
        from jsonb_array_elements(v_prizes) with ordinality as t(p, ord)
        where coalesce((p->>'amount')::numeric,0) = 0
           or coalesce((p->>'amount')::numeric,0) <= v_rest
      ) q
      where q.cum >= v_rand * q.total
      order by q.cum asc limit 1;
      v_amount := coalesce(v_amount, 0);
    end if;
  end if;

  -- 4. Dreh speichern (auch 0 -> Wartestand); Race gegen unique(emp_id,spin_date) abfangen
  begin
    insert into wheel_spins (emp_id, spin_date, amount, source, special_id)
    values (v_emp, v_today, v_amount, v_source, v_special_id);
  exception when unique_violation then
    select * into v_existing from wheel_spins where emp_id = v_emp and spin_date = v_today;
    return jsonb_build_object('amount', v_existing.amount, 'source', v_existing.source,
      'message','Heute schon gedreht — komm morgen wieder!', 'alreadySpun', true);
  end;

  if v_source = 'budget_exhausted' then
    v_msg := 'Der Bonus-Topf für diesen Monat ist ausgeschöpft. Nächsten Monat geht es weiter!';
  elsif v_amount > 0 then
    v_msg := '🎉 Glückwunsch! Du hast ' || v_amount::text || ' € gewonnen!';
  else
    v_msg := 'Diesmal kein Gewinn. Morgen wieder!';
  end if;

  return jsonb_build_object('amount', v_amount, 'source', v_source, 'message', v_msg);
end;
$$;


ALTER FUNCTION "public"."spin_wheel"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."staffing_forecast"("p_project" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not (public.is_management() or (public.is_planner() and p_project = public.get_my_employee_project_id())) then
    return jsonb_build_object('error','nicht berechtigt');
  end if;
  return public.staffing_forecast_core(p_project);
end $$;


ALTER FUNCTION "public"."staffing_forecast"("p_project" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."staffing_forecast_core"("p_project" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare d date := (now() at time zone 'Europe/Berlin')::date;
        cur_yw int := extract(isoyear from d)::int*100 + extract(week from d)::int;
        hi_yw int := cur_yw + 6;
begin
  return jsonb_build_object(
    'project', p_project,
    'project_name', (select name from public.projects where id=p_project),
    'has_forecast', exists(select 1 from public.report_forecast where project_id=p_project and fc_hours>0),
    'weeks', (
      with skills as (
        select lower(project_skill) as skill, round(avg(work_hours),1) as daily_h, count(*) as headcount
        from public.employees where project_id=p_project and status in ('active','training') and project_skill is not null
        group by lower(project_skill)
      ),
      fc as (
        select lower(skill) as skill, year*100+kw as yw, year, kw, sum(fc_hours) as req
        from public.report_forecast where project_id=p_project and (year*100+kw) between cur_yw and hi_yw and fc_hours>0
        group by lower(skill), year, kw
      ),
      pl as (
        select lower(skill) as skill, extract(isoyear from work_date)::int*100+extract(week from work_date)::int as yw,
          extract(isoyear from work_date)::int as year, extract(week from work_date)::int as kw,
          sum(coalesce(net_hours,0)) as planned, count(distinct employee_id) as planned_ma
        from public.shift_assignments where project_id=p_project and work_date > d and work_date <= d + 49
        group by lower(skill), extract(isoyear from work_date)::int, extract(week from work_date)::int
      ),
      cand as (
        select coalesce(fc.skill,pl.skill) as skill, coalesce(fc.yw,pl.yw) as yw,
          coalesce(fc.year,pl.year) as year, coalesce(fc.kw,pl.kw) as kw, fc.req, pl.planned, pl.planned_ma
        from fc full outer join pl on fc.skill=pl.skill and fc.yw=pl.yw
        where coalesce(fc.yw,pl.yw) > cur_yw
      )
      select coalesce(jsonb_agg(jsonb_build_object(
        'skill', c.skill, 'kw', c.kw, 'year', c.year,
        'required_h', round(c.req::numeric,1), 'planned_h', round(c.planned::numeric,1), 'planned_ma', c.planned_ma,
        'absent_ma', (
          select count(distinct e.id) from public.employees e, jsonb_array_elements(coalesce(e.absences,'[]'::jsonb)) a
          where e.project_id=p_project and lower(e.project_skill)=c.skill and (a->>'from') ~ '^\d{4}-\d{2}-\d{2}'
            and (a->>'from')::date <= to_date(c.year||'-'||c.kw,'IYYY-IW')+6
            and coalesce(nullif(a->>'to',''),(a->>'from'))::date >= to_date(c.year||'-'||c.kw,'IYYY-IW')),
        'status', case
            when c.req is null or c.planned is null then 'nicht_vorhersagbar'
            when c.req>0 and c.planned>0 and abs(c.req-c.planned)/greatest(c.req,c.planned) > 0.5 then 'skala_unklar'
            else 'ok' end,
        'scale_ratio', case when c.req>0 and c.planned>0 then round((c.planned/c.req)::numeric,2) else null end,
        'missing', (case when c.req is null then jsonb_build_array('Forecast') else '[]'::jsonb end)
                   || (case when c.planned is null then jsonb_build_array('Schichtplan') else '[]'::jsonb end),
        'gap_h', case when c.req is not null and c.planned is not null then round((c.req - c.planned)::numeric,1) else null end,
        'gap_people', case
            when c.req is not null and c.planned is not null and s.daily_h>0
                 and not (c.req>0 and c.planned>0 and abs(c.req-c.planned)/greatest(c.req,c.planned) > 0.5)
            then round(((c.req - c.planned)/(s.daily_h*5))::numeric) else null end
      ) order by c.kw, c.skill), '[]'::jsonb)
      from cand c left join skills s on s.skill=c.skill
    )
  );
end $$;


ALTER FUNCTION "public"."staffing_forecast_core"("p_project" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."stamp_by_pin"("p_code" "text", "p_action" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_fails  int;
  v_pin    time_pins%rowtype;
  v_emp    employees%rowtype;
  v_sess   time_sessions%rowtype;
  v_today  date := current_date;
  v_now    text := to_char(now() at time zone 'Europe/Berlin', 'HH24:MI');
  v_inm    int; v_outm int; v_gross int; v_pmin int; v_smin int; v_net int;
  v_start  text; v_dur int; v_name text;
begin
  -- Rate-Limit
  select count(*) into v_fails from time_pin_attempts where attempted_at > now() - interval '5 minutes';
  if v_fails >= 5 then
    return jsonb_build_object('ok',false,'error','locked','reason','rate_limit');
  end if;

  -- PIN + Sperre + MA/Status
  select * into v_pin from time_pins where code = p_code;
  if not found then
    delete from time_pin_attempts where attempted_at < now() - interval '1 hour';
    insert into time_pin_attempts default values;
    return jsonb_build_object('ok',false,'error','invalid');
  end if;
  if v_pin.locked_until is not null and v_pin.locked_until > now() then
    return jsonb_build_object('ok',false,'error','locked','reason','pin_locked','until',v_pin.locked_until);
  end if;
  select * into v_emp from employees where id = v_pin.emp_id;
  if not found or v_emp.status not in ('active','training') then
    return jsonb_build_object('ok',false,'error','inactive');
  end if;
  v_name := trim(coalesce(v_emp.first_name,'') || ' ' || coalesce(v_emp.last_name,''));

  -- heutige Session (laufende bevorzugt)
  select * into v_sess from time_sessions
    where emp_id = v_pin.emp_id and session_date = v_today
    order by (clock_out is null) desc, created_at desc limit 1;

  if p_action = 'in' then
    if v_sess.id is not null and v_sess.clock_out is null then
      return jsonb_build_object('ok',false,'error','already_in');
    end if;
    insert into time_sessions(emp_id, session_date, clock_in, clock_out, pauses, smokes)
      values (v_pin.emp_id, v_today, v_now, null, '[]'::jsonb, '[]'::jsonb)
      returning * into v_sess;

  elsif v_sess.id is null or v_sess.clock_out is not null then
    return jsonb_build_object('ok',false,'error','not_clocked_in');

  elsif p_action = 'out' then
    v_inm  := split_part(v_sess.clock_in,':',1)::int*60 + split_part(v_sess.clock_in,':',2)::int;
    v_outm := split_part(v_now,':',1)::int*60 + split_part(v_now,':',2)::int;
    v_gross := greatest(0, v_outm - v_inm);
    select coalesce(sum((e->>'duration')::int),0) into v_pmin from jsonb_array_elements(coalesce(v_sess.pauses,'[]'::jsonb)) e;
    select coalesce(sum((e->>'duration')::int),0) into v_smin from jsonb_array_elements(coalesce(v_sess.smokes,'[]'::jsonb)) e;
    v_net := greatest(0, v_gross - v_pmin - v_smin);
    update time_sessions set clock_out = v_now, pause_active = null, smoke_active = null,
      hours = round(v_net/6.0)/10.0, hours_gross = round(v_gross/6.0)/10.0,
      pause_total = v_pmin, smoke_total = v_smin
      where id = v_sess.id returning * into v_sess;

  elsif p_action = 'pause_start' then
    if v_sess.pause_active is not null or v_sess.smoke_active is not null then
      return jsonb_build_object('ok',false,'error','busy');
    end if;
    update time_sessions set pause_active = v_now where id = v_sess.id returning * into v_sess;

  elsif p_action = 'pause_end' then
    if v_sess.pause_active is null then return jsonb_build_object('ok',false,'error','no_pause'); end if;
    v_start := v_sess.pause_active;
    v_dur := greatest(0, (split_part(v_now,':',1)::int*60 + split_part(v_now,':',2)::int)
                       - (split_part(v_start,':',1)::int*60 + split_part(v_start,':',2)::int));
    update time_sessions set pause_active = null,
      pauses = coalesce(v_sess.pauses,'[]'::jsonb) || jsonb_build_array(jsonb_build_object('start',v_start,'end',v_now,'duration',v_dur))
      where id = v_sess.id returning * into v_sess;

  elsif p_action = 'smoke_start' then
    if v_sess.pause_active is not null or v_sess.smoke_active is not null then
      return jsonb_build_object('ok',false,'error','busy');
    end if;
    update time_sessions set smoke_active = v_now where id = v_sess.id returning * into v_sess;

  elsif p_action = 'smoke_end' then
    if v_sess.smoke_active is null then return jsonb_build_object('ok',false,'error','no_smoke'); end if;
    v_start := v_sess.smoke_active;
    v_dur := greatest(0, (split_part(v_now,':',1)::int*60 + split_part(v_now,':',2)::int)
                       - (split_part(v_start,':',1)::int*60 + split_part(v_start,':',2)::int));
    update time_sessions set smoke_active = null,
      smokes = coalesce(v_sess.smokes,'[]'::jsonb) || jsonb_build_array(jsonb_build_object('start',v_start,'end',v_now,'duration',v_dur))
      where id = v_sess.id returning * into v_sess;

  else
    return jsonb_build_object('ok',false,'error','bad_action');
  end if;

  return jsonb_build_object('ok',true,'emp_name',v_name,'action',p_action,'time',v_now,
    'session_state', jsonb_build_object(
      'id', v_sess.id, 'clock_in', v_sess.clock_in, 'clock_out', v_sess.clock_out,
      'pause_active', v_sess.pause_active, 'smoke_active', v_sess.smoke_active,
      'pauses', coalesce(v_sess.pauses,'[]'::jsonb), 'smokes', coalesce(v_sess.smokes,'[]'::jsonb),
      'hours', v_sess.hours, 'hours_gross', v_sess.hours_gross));
end;
$$;


ALTER FUNCTION "public"."stamp_by_pin"("p_code" "text", "p_action" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."task_can_substitute"("p_project_id" "text", "p_orig_assignee" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select is_management()
      or (p_orig_assignee = auth.uid())
      or (p_project_id is not null and is_planner() and p_project_id = get_my_employee_project_id());
$$;


ALTER FUNCTION "public"."task_can_substitute"("p_project_id" "text", "p_orig_assignee" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."task_open_counts"() RETURNS TABLE("count_key" "text", "project_id" "text", "n" integer)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  -- CVs ohne Aktion: >7 Tage keine Statusaenderung, nicht aktiv, nicht abgelehnt (Spiegel von COCKPIT_FILTERS.cv_stuck)
  select 'cv_stuck'::text, null::text, count(*)::int
    from cvs
   where status is distinct from 'active'
     and status not in ('rejected_by_us','rejected_by_employee','rejected_by_client','no_contact','homeoffice_only','incomplete','blacklist')
     and coalesce(status_changed_at, cv_date::timestamptz) < now() - interval '7 days'
  having count(*) > 0
  union all
  -- Vertraege, die in <=30 Tagen auslaufen (Spiegel von counts.expiring)
  select 'contract_gap'::text, null::text, count(*)::int
    from employees
   where contract->>'end' ~ '^\d{4}-\d{2}-\d{2}'
     and (contract->>'end')::date >= current_date
     and (contract->>'end')::date <= current_date + 30
  having count(*) > 0
  union all
  -- Offene Urlaubsantraege je Projekt des Antragstellers
  select 'vacreq_open'::text, e.project_id::text, count(*)::int
    from vacation_requests vr
    join employees e on e.id = vr.employee_id
   where vr.status = 'pending'
   group by e.project_id
  union all
  -- Wechselkurs fuer den Folgemonat fehlt, faellig ab dem 15. (Spiegel von fxRateReminder)
  select 'fx_missing'::text, null::text, 1
   where extract(day from current_date) >= 15
     and coalesce(
       ((select value from app_config where key = 'jsr_fx_rates_v1')
         ->> to_char(date_trunc('month', current_date) + interval '1 month', 'YYYY-MM'))::numeric,
       0) <= 0;
$$;


ALTER FUNCTION "public"."task_open_counts"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."task_take_over"("p_task_key" "text", "p_project_id" "text", "p_date" "date", "p_orig_assignee" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.task_can_substitute(p_project_id, p_orig_assignee) then
    raise exception 'not authorized to take over this task';
  end if;
  insert into public.task_takeover(task_key, project_id, date, orig_assignee, taken_over_by)
  values (p_task_key, p_project_id, p_date, p_orig_assignee, auth.uid())
  on conflict (task_key, project_id, date, orig_assignee)
  do update set taken_over_by=auth.uid(), taken_over_at=now();
end; $$;


ALTER FUNCTION "public"."task_take_over"("p_task_key" "text", "p_project_id" "text", "p_date" "date", "p_orig_assignee" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."task_toggle_done"("p_task_key" "text", "p_date" "date", "p_assignee_user" "uuid", "p_project_id" "text", "p_done" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not (p_assignee_user = auth.uid() or public.task_can_substitute(p_project_id, p_assignee_user)) then
    raise exception 'not authorized';
  end if;
  if p_done then
    insert into public.daily_tasks_done(task_key, date, assignee_user, project_id, done_by, done_by_name, done_at)
    values (p_task_key, p_date, p_assignee_user, p_project_id, auth.uid(),
            coalesce((select full_name from public.app_users where user_id=auth.uid()), 'jemand'), now())
    on conflict (task_key, date, assignee_user, project_id)
    do update set done_by=auth.uid(), done_by_name=excluded.done_by_name, done_at=now();
  else
    delete from public.daily_tasks_done
     where task_key=p_task_key and date=p_date
       and assignee_user is not distinct from p_assignee_user
       and project_id is not distinct from p_project_id;
  end if;
end; $$;


ALTER FUNCTION "public"."task_toggle_done"("p_task_key" "text", "p_date" "date", "p_assignee_user" "uuid", "p_project_id" "text", "p_done" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_employee_lead"("p_payload" "jsonb") RETURNS "public"."employees"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
declare is_adm boolean; eid uuid; existing_proj text; setlist text; rec public.employees;
begin
  is_adm := public.is_management() or public.is_hr() or public.is_finance();
  if (p_payload->>'id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'id fehlt oder ungueltig.'; end if;
  eid := (p_payload->>'id')::uuid;
  select project_id into existing_proj from public.employees where id = eid;
  if not found then raise exception 'Mitarbeiter nicht gefunden.'; end if;
  if not is_adm then
    if not public.is_planner() or public.perm_mode(auth.uid(),'emp')<>'edit' or not public.perm_proj_ok(auth.uid(),'emp',existing_proj, null) then
      raise exception 'Nicht berechtigt (fremdes oder kein Projekt).'; end if;
    if (p_payload ? 'project_id') and not public.perm_proj_ok(auth.uid(),'emp',(p_payload->>'project_id'), null) then
      raise exception 'Projektwechsel nur in ein erlaubtes Projekt.'; end if;
    p_payload := p_payload - 'fixed_salary' - 'hourly_rate' - 'salary_currency' - 'salary_type' - 'guaranteed_pct' - 'bank' - 'id_number';
    perform set_config('app.lead_employee_write', '1', true);   -- Trigger-Bypass fuer den gevetteten Lead-Write
  end if;
  p_payload := p_payload - 'id';
  select string_agg(quote_ident(k)||'=r.'||quote_ident(k), ',') into setlist
  from jsonb_object_keys(p_payload) as t(k)
  where exists (select 1 from information_schema.columns c
               where c.table_schema='public' and c.table_name='employees' and c.column_name=t.k);
  if setlist is null then select * into rec from public.employees where id = eid; return rec; end if;
  execute format('update public.employees e set %s from jsonb_populate_record(null::public.employees, $1) r where e.id = $2 returning e.*', setlist)
    into rec using p_payload, eid;
  return rec;
end $_$;


ALTER FUNCTION "public"."update_employee_lead"("p_payload" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."usage_day_metrics"("p_from" "date", "p_to" "date") RETURNS TABLE("day" "date", "user_id" "uuid", "user_name" "text", "sessions" integer, "active_minutes" integer, "logins" integer, "writes" integer, "writes_by_entity" "jsonb", "areas" "text"[], "tasks_done" integer, "tasks_empty" integer)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if auth.uid() is not null and not public.is_management() then
    raise exception 'not authorized';
  end if;
  return query
  with
  sess as (
    select s.user_id as uid, s.started_at::date as d,
           count(*)::int as n,
           round(sum(greatest(0, extract(epoch from (s.last_seen - s.started_at))/60)))::int as mins
    from public.user_sessions s
    where s.started_at::date between p_from and p_to
    group by s.user_id, s.started_at::date
  ),
  acts as (
    select l.user_id as uid, l.created_at::date as d, l.action as action, l.entity as entity
    from public.activity_log l
    where l.created_at::date between p_from and p_to and l.user_id is not null
  ),
  logins as ( select uid, d, count(*)::int as n from acts where action='login' group by uid, d ),
  wr as (
    select uid, d, coalesce(entity,'-') as entity, count(*)::int as c
    from acts where action in ('create','update','delete') group by uid, d, coalesce(entity,'-')
  ),
  wr_agg as (
    select uid, d, sum(c)::int as total, jsonb_object_agg(entity, c) as byentity
    from wr group by uid, d
  ),
  vw as (
    select uid, d, array_agg(distinct entity) as areas
    from acts where action='view' and entity is not null group by uid, d
  ),
  tasks as (
    select t.done_by as uid, t.done_at::date as d, count(*)::int as n,
           count(*) filter (where t.session_writes = 0)::int as empty   -- NULL (vor Instrumentierung) zählt NICHT als leer
    from public.daily_tasks_done t
    where t.done_at::date between p_from and p_to and t.done_by is not null
    group by t.done_by, t.done_at::date
  ),
  keys as (
    select uid, d from sess
    union select uid, d from acts
    union select uid, d from tasks
  )
  select k.d, k.uid,
    coalesce((select au.full_name from public.app_users au where au.user_id = k.uid), '') as user_name,
    coalesce(se.n,0), coalesce(se.mins,0), coalesce(lo.n,0),
    coalesce(wa.total,0), coalesce(wa.byentity, '{}'::jsonb), coalesce(vw.areas, '{}'::text[]),
    coalesce(ta.n,0), coalesce(ta.empty,0)
  from (select distinct uid, d from keys) k
  left join sess   se on se.uid=k.uid and se.d=k.d
  left join logins lo on lo.uid=k.uid and lo.d=k.d
  left join wr_agg wa on wa.uid=k.uid and wa.d=k.d
  left join vw     vw on vw.uid=k.uid and vw.d=k.d
  left join tasks  ta on ta.uid=k.uid and ta.d=k.d
  order by k.d desc, user_name;
end $$;


ALTER FUNCTION "public"."usage_day_metrics"("p_from" "date", "p_to" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."usage_user_detail"("p_user" "uuid", "p_days" integer DEFAULT 42) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  d_from date := current_date - (greatest(p_days,7) - 1);
  v_daily jsonb; v_sessions jsonb; v_areas jsonb; v_changes jsonb; v_digests jsonb;
  last_active timestamptz; act7 int; act_prev int; empty_tasks int; done_tasks int; snoozed int;
  anom text[] := '{}';
begin
  if auth.uid() is not null and not public.is_management() then raise exception 'not authorized'; end if;

  with days as (select generate_series(d_from, current_date, interval '1 day')::date dd),
  se as (select started_at::date d, count(*) n, round(sum(greatest(0, extract(epoch from (last_seen-started_at))/60)))::int mins
         from public.user_sessions where user_id=p_user and started_at::date between d_from and current_date group by 1),
  al as (select created_at::date d, action, entity from public.activity_log where user_id=p_user and created_at::date between d_from and current_date),
  wr as (select d, count(*) n from al where action in ('create','update','delete') group by d),
  vw as (select d, count(*) n from al where action='view' group by d),
  ta as (select done_at::date d, count(*) n, count(*) filter (where session_writes=0) e
         from public.daily_tasks_done where done_by=p_user and done_at::date between d_from and current_date group by 1)
  select jsonb_agg(jsonb_build_object('day',dd,'sessions',coalesce(se.n,0),'minutes',coalesce(se.mins,0),
           'writes',coalesce(wr.n,0),'views',coalesce(vw.n,0),'tasks_done',coalesce(ta.n,0),'tasks_empty',coalesce(ta.e,0)) order by dd)
    into v_daily from days
    left join se on se.d=days.dd left join wr on wr.d=days.dd left join vw on vw.d=days.dd left join ta on ta.d=days.dd;

  select jsonb_agg(jsonb_build_object('started_at',started_at,'last_seen',last_seen,
           'minutes',round(greatest(0, extract(epoch from (last_seen-started_at))/60))::int,'pings',ping_count) order by started_at desc)
    into v_sessions from (select * from public.user_sessions where user_id=p_user order by started_at desc limit 25) s;

  select jsonb_agg(jsonb_build_object('area',entity,'count',n) order by n desc)
    into v_areas from (select entity, count(*) n from public.activity_log
      where user_id=p_user and action='view' and entity is not null and created_at::date>=d_from group by entity) x;

  select jsonb_agg(jsonb_build_object('entity',entity,'count',n) order by n desc)
    into v_changes from (select coalesce(entity,'-') entity, count(*) n from public.activity_log
      where user_id=p_user and action in ('create','update','delete') and created_at::date>=d_from group by 1) x;

  select count(*), count(*) filter (where session_writes=0) into done_tasks, empty_tasks
    from public.daily_tasks_done where done_by=p_user and done_at::date>=d_from;
  select count(*) into snoozed from public.task_snooze where user_id=p_user and date>=d_from;

  select jsonb_agg(jsonb_build_object('day',day,'summary',summary) order by day desc)
    into v_digests from (select day, summary from public.usage_digests where user_id=p_user and day>=d_from order by day desc limit p_days) x;

  -- Auffälligkeiten
  select greatest(coalesce(max(created_at),'epoch'::timestamptz),
                  coalesce((select max(last_seen) from public.user_sessions where user_id=p_user),'epoch'::timestamptz))
    into last_active from public.activity_log where user_id=p_user;
  if coalesce(empty_tasks,0) >= 3 and coalesce(empty_tasks,0) >= 0.5*greatest(coalesce(done_tasks,0),1) then
    anom := anom || 'dauerhaft leere Häkchen'; end if;
  if last_active is null or last_active < now()-interval '7 days' then
    anom := anom || ('länger nicht aktiv'||case when last_active > 'epoch'::timestamptz then ' (seit '||extract(day from now()-last_active)::int||' Tagen)' else '' end);
  end if;
  select count(distinct created_at::date) into act7 from public.activity_log where user_id=p_user and created_at>=now()-interval '7 days';
  select count(distinct created_at::date) into act_prev from public.activity_log where user_id=p_user and created_at>=now()-interval '28 days' and created_at<now()-interval '7 days';
  if coalesce(act_prev,0) >= 8 and coalesce(act7,0) = 0 then anom := anom || 'Aktivität plötzlich abgebrochen'; end if;

  return jsonb_build_object(
    'daily', coalesce(v_daily,'[]'::jsonb), 'sessions', coalesce(v_sessions,'[]'::jsonb),
    'areas', coalesce(v_areas,'[]'::jsonb), 'changes', coalesce(v_changes,'[]'::jsonb),
    'tasks', jsonb_build_object('done',coalesce(done_tasks,0),'empty',coalesce(empty_tasks,0),'snoozed',coalesce(snoozed,0)),
    'digests', coalesce(v_digests,'[]'::jsonb), 'anomalies', to_jsonb(anom),
    'last_active', last_active);
end $$;


ALTER FUNCTION "public"."usage_user_detail"("p_user" "uuid", "p_days" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."vorort_lookup"("p_station" "text", "p_code" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
declare v public.cvs; n int;
begin
  if not public.vorort_station_ok(p_station) then return jsonb_build_object('ok', false, 'code', 'station'); end if;
  select count(*) into n from public.vorort_attempts where at > now() - interval '5 minutes';
  if n >= 12 then return jsonb_build_object('ok', false, 'code', 'locked'); end if;
  if coalesce(p_code,'') !~ '^\d{6}$' then
    insert into public.vorort_attempts default values;
    return jsonb_build_object('ok', false, 'code', 'notfound');
  end if;
  select * into v from public.cvs where public_code = p_code limit 1;
  if not found then
    insert into public.vorort_attempts default values;
    return jsonb_build_object('ok', false, 'code', 'notfound');
  end if;
  return jsonb_build_object('ok', true, 'cv', jsonb_build_object(
    'public_code', v.public_code, 'first_name', v.first_name, 'last_name', v.last_name,
    'email', v.email, 'phone', v.phone,
    'street', v.street, 'postal_code', v.postal_code, 'city', v.city, 'country', v.country,
    'birthday', v.birthday,
    'education', v.education, 'education_level', v.education_level, 'experience_years', v.experience_years,
    'work_history', v.work_history, 'language_level', v.language_level, 'writing_level', v.writing_level,
    'languages_str', v.languages_str, 'available_from', v.available_from, 'homeoffice_pref', v.homeoffice_pref,
    'extra', coalesce(v.extra, '{}'::jsonb)));
end $_$;


ALTER FUNCTION "public"."vorort_lookup"("p_station" "text", "p_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."vorort_station_ok"("p_station" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1 from public.app_config
    where key='jsr_vorort_station_v1'
      and coalesce((value->>'active')::boolean, false)
      and value->>'token' = p_station
      and coalesce(p_station,'') <> ''
  );
$$;


ALTER FUNCTION "public"."vorort_station_ok"("p_station" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."vorort_submit"("p_station" "text", "p_code" "text", "p_data" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v public.cvs;
begin
  if not public.vorort_station_ok(p_station) then return jsonb_build_object('ok', false, 'code', 'station'); end if;
  select * into v from public.cvs where public_code = p_code limit 1;
  if not found then return jsonb_build_object('ok', false, 'code', 'notfound'); end if;
  update public.cvs set
    first_name       = case when p_data ? 'first_name'       then nullif(p_data->>'first_name','')            else first_name end,
    last_name        = case when p_data ? 'last_name'        then nullif(p_data->>'last_name','')             else last_name end,
    email            = case when p_data ? 'email'            then nullif(p_data->>'email','')                 else email end,
    phone            = case when p_data ? 'phone'            then nullif(p_data->>'phone','')                 else phone end,
    street           = case when p_data ? 'street'           then nullif(p_data->>'street','')                else street end,
    postal_code      = case when p_data ? 'postal_code'      then nullif(p_data->>'postal_code','')           else postal_code end,
    city             = case when p_data ? 'city'             then nullif(p_data->>'city','')                  else city end,
    country          = case when p_data ? 'country'          then nullif(p_data->>'country','')               else country end,
    birthday         = case when p_data ? 'birthday'         then nullif(p_data->>'birthday','')::date        else birthday end,
    education        = case when p_data ? 'education'        then nullif(p_data->>'education','')             else education end,
    education_level  = case when p_data ? 'education_level'  then nullif(p_data->>'education_level','')       else education_level end,
    experience_years = case when p_data ? 'experience_years' then nullif(p_data->>'experience_years','')::int else experience_years end,
    work_history     = case when p_data ? 'work_history'     then nullif(p_data->>'work_history','')          else work_history end,
    language_level   = case when p_data ? 'language_level'   then nullif(p_data->>'language_level','')        else language_level end,
    writing_level    = case when p_data ? 'writing_level'    then nullif(p_data->>'writing_level','')         else writing_level end,
    languages_str    = case when p_data ? 'languages_str'    then nullif(p_data->>'languages_str','')         else languages_str end,
    available_from   = case when p_data ? 'available_from'   then nullif(p_data->>'available_from','')::date  else available_from end,
    homeoffice_pref  = case when p_data ? 'homeoffice_pref'  then nullif(p_data->>'homeoffice_pref','')       else homeoffice_pref end,
    extra            = coalesce(extra,'{}'::jsonb) || coalesce(p_data->'extra','{}'::jsonb) || jsonb_build_object('vorort_at', now()),
    updated_at       = now()
  where public_code = p_code;
  return jsonb_build_object('ok', true, 'public_code', p_code);
end $$;


ALTER FUNCTION "public"."vorort_submit"("p_station" "text", "p_code" "text", "p_data" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."windsor_leads_auto_discard"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if NEW.status_review = 'dup' and NEW.imported_cv_id is not null then
    if exists (
      select 1 from public.cvs c
       where c.id = NEW.imported_cv_id
         and c.status in ('blacklist','no_contact','rejected_by_us','rejected_by_employee')
    ) then
      NEW.status_review := 'auto_discarded';
    end if;
  end if;
  return NEW;
end $$;


ALTER FUNCTION "public"."windsor_leads_auto_discard"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."windsor_marketing_dedup"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  if pg_trigger_depth() > 1 then return null; end if;   -- Re-Insert unten nicht erneut deduppen
  drop table if exists _wm_merge;
  create temp table _wm_merge as
    select datasource, date, campaign,
      max(account_name) account_name, max(source) source, max(spend) spend, max(impressions) impressions,
      max(clicks) clicks, max(reach) reach, max(followers_count) followers_count
    from public.windsor_marketing
    group by datasource, date, campaign
    having count(*) > 1;
  if (select count(*) from _wm_merge) = 0 then drop table _wm_merge; return null; end if;
  delete from public.windsor_marketing d
   where exists (select 1 from _wm_merge m where m.datasource is not distinct from d.datasource
     and m.date is not distinct from d.date and m.campaign is not distinct from d.campaign);
  insert into public.windsor_marketing(datasource,date,campaign,account_name,source,spend,impressions,clicks,reach,followers_count)
    select datasource,date,campaign,account_name,source,spend,impressions,clicks,reach,followers_count from _wm_merge;
  drop table _wm_merge;
  return null;
end $$;


ALTER FUNCTION "public"."windsor_marketing_dedup"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."windsor_marketing_merge"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  update public.windsor_marketing set
    account_name    = coalesce(new.account_name, account_name),
    source          = coalesce(new.source, source),
    spend           = coalesce(new.spend, spend),
    impressions     = coalesce(new.impressions, impressions),
    clicks          = coalesce(new.clicks, clicks),
    reach           = coalesce(new.reach, reach),
    followers_count = coalesce(new.followers_count, followers_count)
  where datasource is not distinct from new.datasource
    and date       is not distinct from new.date
    and campaign   is not distinct from new.campaign;
  if found then return null; end if;   -- in bestehende Zeile gemergt → Insert überspringen
  return new;                          -- keine Kollision → normal einfügen
end $$;


ALTER FUNCTION "public"."windsor_marketing_merge"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."call_criteria" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text",
    "skill" "text",
    "category" "text",
    "order_index" integer DEFAULT 0 NOT NULL,
    "prompt" "text" NOT NULL,
    "type" "text" DEFAULT 'points'::"text" NOT NULL,
    "max_points" numeric DEFAULT 1 NOT NULL,
    "weight" numeric DEFAULT 1 NOT NULL,
    "allow_na" boolean DEFAULT true NOT NULL,
    "hint" "text",
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "agent_hint" "text",
    "level_hints" "jsonb",
    "compliance_critical" boolean DEFAULT false NOT NULL,
    CONSTRAINT "call_criteria_type_check" CHECK (("type" = ANY (ARRAY['points'::"text", 'yesno'::"text", 'tristate'::"text", 'grade'::"text"])))
);


ALTER TABLE "public"."call_criteria" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."call_samples" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "sampled_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "kw" integer,
    "year" integer,
    "project_id" "text",
    "skill" "text",
    "criteria_scope" "text",
    "call_ref" "text",
    "note" "text",
    "total_pct" numeric,
    "status" "text" DEFAULT 'done'::"text" NOT NULL,
    "conducted_by" "uuid",
    "conducted_by_name" "text",
    "conducted_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "total_points" numeric,
    "max_points" numeric,
    "feedback_text" "text",
    "compliance_failed" boolean DEFAULT false NOT NULL,
    "raw_points" numeric,
    CONSTRAINT "call_samples_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'done'::"text"])))
);


ALTER TABLE "public"."call_samples" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."call_scores" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "sample_id" "uuid" NOT NULL,
    "criterion_id" "uuid",
    "order_index" integer,
    "category_snapshot" "text",
    "prompt_snapshot" "text" NOT NULL,
    "type_snapshot" "text" NOT NULL,
    "max_points_snapshot" numeric DEFAULT 1 NOT NULL,
    "weight_snapshot" numeric DEFAULT 1 NOT NULL,
    "points" numeric,
    "na" boolean DEFAULT false NOT NULL,
    "comment" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "level_hints_snapshot" "jsonb",
    "compliance_critical_snapshot" boolean DEFAULT false NOT NULL,
    CONSTRAINT "call_scores_type_snapshot_check" CHECK (("type_snapshot" = ANY (ARRAY['points'::"text", 'yesno'::"text", 'tristate'::"text", 'grade'::"text"])))
);


ALTER TABLE "public"."call_scores" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."app_users" (
    "user_id" "uuid" NOT NULL,
    "role_keys" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "full_name" "text",
    "staff_number" "text",
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "client_id" "text",
    "employee_id" "uuid",
    "must_change_pw" boolean DEFAULT false NOT NULL,
    "mgmt_external" boolean DEFAULT false NOT NULL,
    CONSTRAINT "app_users_kunde_exclusive" CHECK (((NOT ('kunde'::"text" = ANY ("role_keys"))) OR ("role_keys" <@ ARRAY['kunde'::"text"])))
);


ALTER TABLE "public"."app_users" OWNER TO "postgres";


COMMENT ON COLUMN "public"."app_users"."client_id" IS 'Verknüpfung zu client_accounts.id — nur Client-Portal-User';



COMMENT ON COLUMN "public"."app_users"."employee_id" IS 'Verknuepfung zu employees.id (ersetzt jsr_emp_user_links_v1)';



COMMENT ON COLUMN "public"."app_users"."mgmt_external" IS 'Management-Zugang OHNE eigene Aufgaben-Partition (Manager extern). Gleiche Rechte/Sichtbarkeit wie internes Management; steuert NUR, ob eine eigene Tagesaufgaben-Liste erzeugt wird. Für Nicht-Management-Rollen ohne Wirkung.';



CREATE TABLE IF NOT EXISTS "public"."daily_hours" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "import_id" "uuid",
    "project_id" "text" NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "work_date" "date" NOT NULL,
    "skill" "text",
    "hours" numeric,
    "pause_hours" numeric,
    "sales_calls" integer,
    "raw" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."daily_hours" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."kpi_config" (
    "id" "text" NOT NULL,
    "project_id" "text",
    "skill" "text",
    "name" "text",
    "type" "text",
    "unit" "text",
    "thresholds" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "level" "text" DEFAULT 'agent'::"text" NOT NULL,
    "is_primary" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."kpi_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."kpi_entries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "emp_id" "uuid",
    "kw" integer,
    "year" integer,
    "kpi_id" "text",
    "value" numeric,
    "entered_by" "text",
    "ts" timestamp with time zone DEFAULT "now"(),
    "source" "text",
    "import_id" "uuid",
    "source_row" integer,
    "raw" "jsonb"
);


ALTER TABLE "public"."kpi_entries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."kpi_project_entries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text" NOT NULL,
    "skill" "text" DEFAULT ''::"text" NOT NULL,
    "kw" integer,
    "year" integer,
    "kpi_id" "text",
    "value" numeric,
    "entered_by" "text",
    "ts" timestamp with time zone DEFAULT "now"(),
    "month" integer,
    "source" "text",
    "import_id" "uuid",
    "source_row" integer,
    "raw" "jsonb",
    CONSTRAINT "kpi_project_entries_period_chk" CHECK (((("kw" IS NOT NULL) AND ("month" IS NULL)) OR (("kw" IS NULL) AND ("month" IS NOT NULL))))
);


ALTER TABLE "public"."kpi_project_entries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."projects" (
    "id" "text" NOT NULL,
    "name" "text",
    "client" "text",
    "status" "text",
    "location" "text",
    "rate_active" numeric,
    "rate_training" numeric,
    "billing_mode" "text",
    "monthly_flat" numeric,
    "ai_translation_enabled" boolean,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "contract_start" "text",
    "contract_end" "text",
    "language_requirement" "text",
    "description" "text",
    "monthly_hours_per_agent" numeric,
    "billing_type" "text",
    "minute_rate" numeric,
    "case_price" numeric,
    "case_aht_sec" numeric,
    "cpo_amount" numeric,
    "cpo_per_hour" numeric,
    "flat_per_agent" numeric,
    "productive_hours" numeric,
    "efficiency_pct" numeric,
    "training_mode" "text",
    "training_flat" numeric,
    "color" "text",
    "allow_global_bogen" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."projects" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."report_forecast" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text" NOT NULL,
    "skill" "text" NOT NULL,
    "year" integer NOT NULL,
    "kw" integer NOT NULL,
    "fc_hours" numeric,
    "file_name" "text",
    "updated_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "planned_hours" numeric
);


ALTER TABLE "public"."report_forecast" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."report_fte" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text" NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "fte" numeric DEFAULT 1 NOT NULL,
    "updated_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."report_fte" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."report_longterm" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text" NOT NULL,
    "skill" "text" NOT NULL,
    "start_year" integer,
    "start_month" integer,
    "rows" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "file_name" "text",
    "updated_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."report_longterm" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."report_measures" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text" NOT NULL,
    "skill" "text" DEFAULT 'sales'::"text" NOT NULL,
    "text" "text" NOT NULL,
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "comment" "text",
    "created_year" integer NOT NULL,
    "created_kw" integer NOT NULL,
    "done_year" integer,
    "done_kw" integer,
    "seq" integer DEFAULT 0 NOT NULL,
    "created_by" "uuid",
    "created_by_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "report_measures_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'in_progress'::"text", 'done'::"text"])))
);


ALTER TABLE "public"."report_measures" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shift_assignments" (
    "project_id" "text" NOT NULL,
    "skill" "text" DEFAULT 'all'::"text" NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "work_date" "date" NOT NULL,
    "shift_id" "text",
    "label" "text",
    "shift_value" "text",
    "value2" "text",
    "net_hours" numeric,
    "gross_hours" numeric,
    "pause_duration" numeric,
    "pause_paid" boolean,
    "split" boolean DEFAULT false NOT NULL,
    "slots" "jsonb",
    "updated_by" "uuid",
    "updated_by_name" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "shift" "jsonb"
);


ALTER TABLE "public"."shift_assignments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."weekly_calls" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "import_id" "uuid",
    "project_id" "text" NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "kw" integer NOT NULL,
    "year" integer NOT NULL,
    "answered" integer,
    "outbound" integer,
    "no_answer" integer,
    "avg_handle_sec" numeric,
    "avg_talk_sec" numeric,
    "avg_hold_sec" numeric,
    "avg_acw_sec" numeric,
    "raw" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "transferred" integer,
    "held" integer
);


ALTER TABLE "public"."weekly_calls" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."weekly_gauges" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "import_id" "uuid",
    "project_id" "text" NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "kw" integer NOT NULL,
    "year" integer NOT NULL,
    "gesamt_pct" numeric,
    "anzahl" integer,
    "dauer_sec" numeric,
    "nps" numeric,
    "csat" numeric,
    "raw" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."weekly_gauges" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."data_imports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text" NOT NULL,
    "source_type" "text" NOT NULL,
    "kw" integer,
    "year" integer,
    "file_name" "text",
    "file_hash" "text",
    "storage_path" "text",
    "status" "text" DEFAULT 'ok'::"text" NOT NULL,
    "warnings" "jsonb",
    "row_count" integer,
    "matched_count" integer,
    "unmatched_count" integer,
    "uploaded_by" "uuid",
    "uploaded_by_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "data_imports_source_type_check" CHECK (("source_type" = ANY (ARRAY['rohdaten'::"text", 'calls'::"text", 'calls_inbound'::"text", 'gauges'::"text", 'booking'::"text", 'booking_a'::"text", 'booking_week'::"text", 'booking_month'::"text", 'forecast_sales'::"text", 'forecast_support'::"text", 'longterm'::"text", 'mailer'::"text"]))),
    CONSTRAINT "data_imports_status_check" CHECK (("status" = ANY (ARRAY['ok'::"text", 'partial'::"text", 'error'::"text"])))
);


ALTER TABLE "public"."data_imports" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."weekly_hours_legacy" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "import_id" "uuid",
    "project_id" "text" NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "kw" integer NOT NULL,
    "year" integer NOT NULL,
    "skill" "text",
    "hours" numeric,
    "pause_hours" numeric,
    "raw" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "sales_calls" integer
);


ALTER TABLE "public"."weekly_hours_legacy" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."weekly_hours" WITH ("security_invoker"='true') AS
 WITH "da" AS (
         SELECT "d"."project_id",
            "d"."employee_id",
            (EXTRACT(isoyear FROM "d"."work_date"))::integer AS "year",
            (EXTRACT(week FROM "d"."work_date"))::integer AS "kw",
            "sum"("d"."hours") AS "hours",
            "sum"("d"."pause_hours") AS "pause_hours",
            ("sum"("d"."sales_calls"))::integer AS "sales_calls",
            "max"("d"."skill") AS "skill",
            ("array_agg"("d"."import_id" ORDER BY "di"."created_at" DESC NULLS LAST))[1] AS "import_id",
            COALESCE("max"("di"."created_at"), '1900-01-01 00:00:00+00'::timestamp with time zone) AS "src_created"
           FROM ("public"."daily_hours" "d"
             LEFT JOIN "public"."data_imports" "di" ON (("di"."id" = "d"."import_id")))
          GROUP BY "d"."project_id", "d"."employee_id", (EXTRACT(isoyear FROM "d"."work_date")), (EXTRACT(week FROM "d"."work_date"))
        ), "lg" AS (
         SELECT "l"."id",
            "l"."import_id",
            "l"."project_id",
            "l"."employee_id",
            "l"."kw",
            "l"."year",
            "l"."skill",
            "l"."hours",
            "l"."pause_hours",
            "l"."raw",
            "l"."created_at",
            "l"."sales_calls",
            COALESCE("li"."created_at", '1900-01-01 00:00:00+00'::timestamp with time zone) AS "leg_created"
           FROM ("public"."weekly_hours_legacy" "l"
             LEFT JOIN "public"."data_imports" "li" ON (("li"."id" = "l"."import_id")))
        )
 SELECT ("md5"((((((("da"."project_id" || '|'::"text") || ("da"."employee_id")::"text") || '|'::"text") || "da"."kw") || '|'::"text") || "da"."year")))::"uuid" AS "id",
    "da"."import_id",
    "da"."project_id",
    "da"."employee_id",
    "da"."kw",
    "da"."year",
    "da"."skill",
    "da"."hours",
    "da"."pause_hours",
    NULL::"jsonb" AS "raw",
    "da"."src_created" AS "created_at",
    "da"."sales_calls",
    true AS "from_daily"
   FROM ("da"
     LEFT JOIN "lg" ON ((("lg"."project_id" = "da"."project_id") AND ("lg"."employee_id" = "da"."employee_id") AND ("lg"."kw" = "da"."kw") AND ("lg"."year" = "da"."year"))))
  WHERE (("lg"."employee_id" IS NULL) OR ("da"."src_created" >= "lg"."leg_created"))
UNION ALL
 SELECT "lg"."id",
    "lg"."import_id",
    "lg"."project_id",
    "lg"."employee_id",
    "lg"."kw",
    "lg"."year",
    "lg"."skill",
    "lg"."hours",
    "lg"."pause_hours",
    "lg"."raw",
    "lg"."created_at",
    "lg"."sales_calls",
    false AS "from_daily"
   FROM ("lg"
     LEFT JOIN "da" ON ((("da"."project_id" = "lg"."project_id") AND ("da"."employee_id" = "lg"."employee_id") AND ("da"."kw" = "lg"."kw") AND ("da"."year" = "lg"."year"))))
  WHERE (("da"."employee_id" IS NULL) OR ("lg"."leg_created" > "da"."src_created"));


ALTER VIEW "public"."weekly_hours" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."windsor_marketing" (
    "date" "date",
    "datasource" "text",
    "account_name" "text",
    "source" "text",
    "campaign" "text",
    "spend" numeric,
    "impressions" numeric,
    "clicks" numeric,
    "reach" numeric,
    "followers_count" numeric
);


ALTER TABLE "public"."windsor_marketing" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."activity_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "user_name" "text",
    "action" "text" NOT NULL,
    "entity" "text",
    "entity_id" "text",
    "entity_label" "text",
    "details" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."activity_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."agent_action_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "insight_id" bigint,
    "action_key" "text" NOT NULL,
    "actor" "uuid",
    "target_count" integer,
    "detail" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."agent_action_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."agent_actions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "agent_key" "text" NOT NULL,
    "kind" "text" NOT NULL,
    "at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "meta" "jsonb"
);


ALTER TABLE "public"."agent_actions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."agent_checks" (
    "agent_key" "text" NOT NULL,
    "last_checked_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_day" "date",
    "found_count" integer DEFAULT 0 NOT NULL,
    "metrics" "jsonb",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."agent_checks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."agent_conversations" (
    "id" bigint NOT NULL,
    "user_id" "uuid" NOT NULL,
    "agent_key" "text" NOT NULL,
    "question" "text" NOT NULL,
    "answer" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "session_id" "uuid"
);


ALTER TABLE "public"."agent_conversations" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."agent_conversations_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."agent_conversations_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."agent_conversations_id_seq" OWNED BY "public"."agent_conversations"."id";



CREATE TABLE IF NOT EXISTS "public"."agent_digests" (
    "day" "date" NOT NULL,
    "agent_key" "text" NOT NULL,
    "name" "text",
    "summary" "text",
    "metrics" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."agent_digests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."agent_escalations" (
    "id" bigint NOT NULL,
    "user_id" "uuid" NOT NULL,
    "subject" "text" DEFAULT 'tasks'::"text" NOT NULL,
    "stage" integer DEFAULT 1 NOT NULL,
    "open_count" integer,
    "opened_on" "date" DEFAULT CURRENT_DATE NOT NULL,
    "last_tick" "date",
    "escalated_at" timestamp with time zone,
    "resolved_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."agent_escalations" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."agent_escalations_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."agent_escalations_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."agent_escalations_id_seq" OWNED BY "public"."agent_escalations"."id";



CREATE TABLE IF NOT EXISTS "public"."agent_handoffs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "day" "date" NOT NULL,
    "topic" "text" NOT NULL,
    "by_agent" "text",
    "contributors" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "insight" "text" NOT NULL,
    "severity" "text" DEFAULT 'info'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "resolved_at" timestamp with time zone,
    "thread" "jsonb"
);


ALTER TABLE "public"."agent_handoffs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."agent_insights" (
    "id" bigint NOT NULL,
    "agent_key" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "observation_id" bigint,
    "okey" "text" NOT NULL,
    "day" "date" NOT NULL,
    "title" "text" NOT NULL,
    "severity" "text" DEFAULT 'info'::"text" NOT NULL,
    "context" "text"[],
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "seen_at" timestamp with time zone,
    "dismissed_at" timestamp with time zone,
    "acted_at" timestamp with time zone,
    "facts" "jsonb",
    "confidence" "text",
    "action" "jsonb",
    "disputed_at" timestamp with time zone,
    "dispute_reason" "text"
);


ALTER TABLE "public"."agent_insights" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."agent_insights_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."agent_insights_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."agent_insights_id_seq" OWNED BY "public"."agent_insights"."id";



CREATE TABLE IF NOT EXISTS "public"."agent_observations" (
    "id" bigint NOT NULL,
    "agent_key" "text" NOT NULL,
    "day" "date" NOT NULL,
    "okey" "text" NOT NULL,
    "severity" "text" DEFAULT 'info'::"text" NOT NULL,
    "title" "text" NOT NULL,
    "metrics" "jsonb",
    "confidence" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "resolved_at" timestamp with time zone,
    "facts" "jsonb",
    "project_id" "text",
    "skill" "text"
);


ALTER TABLE "public"."agent_observations" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."agent_observations_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."agent_observations_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."agent_observations_id_seq" OWNED BY "public"."agent_observations"."id";



CREATE TABLE IF NOT EXISTS "public"."agent_prefs" (
    "user_id" "uuid" NOT NULL,
    "settings" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."agent_prefs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ai_access_prefs" (
    "user_id" "uuid" NOT NULL,
    "settings" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."ai_access_prefs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ai_agents" (
    "key" "text" NOT NULL,
    "name" "text" NOT NULL,
    "tagline" "text",
    "avatar_url" "text",
    "accent" "text" DEFAULT '#0F5661'::"text",
    "domain" "text",
    "capabilities" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "where_keys" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "outward_facing" boolean DEFAULT false NOT NULL,
    "disclosure" "text",
    "decision_authority" "jsonb" DEFAULT '{"darf": [], "darf_nicht": []}'::"jsonb" NOT NULL,
    "visibility" "text" DEFAULT 'all'::"text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "seq" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "email" "text",
    "mail_from_name" "text",
    "persona" "text",
    "voice" "jsonb",
    "guardrails" "jsonb",
    "char_text" "text",
    "focus_text" "text",
    "language_text" "text",
    CONSTRAINT "ai_agents_visibility_check" CHECK (("visibility" = ANY (ARRAY['all'::"text", 'management'::"text", 'admin'::"text"])))
);


ALTER TABLE "public"."ai_agents" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."app_config" (
    "key" "text" NOT NULL,
    "value" "jsonb",
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."app_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."applicant_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cv_id" "uuid" NOT NULL,
    "channel" "text" DEFAULT 'email'::"text" NOT NULL,
    "purpose" "text" DEFAULT 'enrich_invite'::"text" NOT NULL,
    "origin" "text" NOT NULL,
    "sender_key" "text",
    "to_address" "text",
    "invite_token" "text",
    "form_id" "uuid",
    "status" "text" NOT NULL,
    "error" "text",
    "provider_id" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "sent_at" timestamp with time zone
);


ALTER TABLE "public"."applicant_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."assistant_gaps" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "question" "text" NOT NULL,
    "asked_by" "uuid",
    "resolved" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."assistant_gaps" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."calendar_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "project_id" "text",
    "kind" "text" DEFAULT 'manual'::"text" NOT NULL,
    "auto_key" "text",
    "start_date" "date" NOT NULL,
    "start_time" time without time zone,
    "end_time" time without time zone,
    "recurrence" "text" DEFAULT 'none'::"text" NOT NULL,
    "until_date" "date",
    "visible_roles" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "created_by" "uuid",
    "created_by_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "participants" "uuid"[] DEFAULT '{}'::"uuid"[] NOT NULL,
    "important" boolean DEFAULT false NOT NULL,
    "meeting_url" "text",
    CONSTRAINT "calendar_events_kind_chk" CHECK (("kind" = ANY (ARRAY['manual'::"text", 'auto'::"text"]))),
    CONSTRAINT "calendar_events_recurrence_chk" CHECK (("recurrence" = ANY (ARRAY['none'::"text", 'weekly'::"text", 'biweekly'::"text", 'monthly'::"text"])))
);


ALTER TABLE "public"."calendar_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."calendar_overrides" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "event_id" "uuid" NOT NULL,
    "occurrence_date" "date" NOT NULL,
    "hidden" boolean DEFAULT false NOT NULL,
    "done" boolean DEFAULT false NOT NULL,
    "done_by" "uuid",
    "done_by_name" "text",
    "done_at" timestamp with time zone,
    "note" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."calendar_overrides" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."call_score_config" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text",
    "skill" "text",
    "green_min" numeric DEFAULT 90 NOT NULL,
    "yellow_min" numeric DEFAULT 75 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "threshold_unit" "text" DEFAULT 'percent'::"text" NOT NULL,
    "feedback_green" "text",
    "feedback_amber" "text",
    "feedback_red" "text",
    CONSTRAINT "call_score_config_threshold_unit_check" CHECK (("threshold_unit" = ANY (ARRAY['percent'::"text", 'points'::"text"])))
);


ALTER TABLE "public"."call_score_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_flags" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "message_id" "uuid",
    "thread_id" "uuid",
    "from_emp_id" "uuid",
    "from_name" "text",
    "category" "text",
    "excerpt" "text",
    "sent_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reviewed_at" timestamp with time zone,
    "reviewed_by" "text"
);


ALTER TABLE "public"."chat_flags" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."chat_universal_contacts" WITH ("security_invoker"='false', "security_barrier"='true') AS
 SELECT DISTINCT "e"."id",
    "e"."first_name",
    "e"."last_name",
    "e"."position",
    "e"."photo_url",
    ("e"."extra" ->> 'photo_color'::"text") AS "photo_color",
    "au"."role_keys"
   FROM ("public"."employees" "e"
     JOIN "public"."app_users" "au" ON (("au"."employee_id" = "e"."id")))
  WHERE (("au"."active" IS NOT FALSE) AND (('hr'::"text" = ANY ("au"."role_keys")) OR (('management'::"text" = ANY ("au"."role_keys")) AND (COALESCE("au"."mgmt_external", false) = false))));


ALTER VIEW "public"."chat_universal_contacts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."clara_handovers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cv_id" "uuid" NOT NULL,
    "reason" "text" NOT NULL,
    "phase" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "resolved_at" timestamp with time zone,
    "resolved_by" "uuid",
    "note" "text"
);


ALTER TABLE "public"."clara_handovers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."clara_rejections" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cv_id" "uuid" NOT NULL,
    "reject_status" "text" NOT NULL,
    "scheduled_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "due_at" timestamp with time zone NOT NULL,
    "sent_at" timestamp with time zone,
    "cancelled_at" timestamp with time zone,
    "cancel_reason" "text",
    "message_id" "text",
    "error" "text"
);


ALTER TABLE "public"."clara_rejections" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."client_accounts" (
    "id" "text" NOT NULL,
    "company_name" "text" NOT NULL,
    "company_legal" "text",
    "industry" "text",
    "website" "text",
    "contact_name" "text",
    "contact_title" "text",
    "contact_email" "text",
    "contact_phone" "text",
    "project_name" "text",
    "project_id" "text",
    "contract_start" "date",
    "contract_end" "date",
    "billing_model" "text",
    "billing_rate" numeric,
    "billing_currency" "text" DEFAULT 'EUR'::"text",
    "payment_terms" "text",
    "vat_id" "text",
    "login_email" "text",
    "active" boolean DEFAULT true,
    "must_change_pw" boolean DEFAULT false,
    "visible_tabs" "text"[] DEFAULT ARRAY['dashboard'::"text", 'team'::"text", 'kpi'::"text", 'shifts'::"text", 'messages'::"text", 'files'::"text"],
    "logo_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "contact2_name" "text",
    "contact2_email" "text",
    "contact2_phone" "text",
    "address_street" "text",
    "address_city" "text",
    "address_country" "text",
    "notes" "text"
);


ALTER TABLE "public"."client_accounts" OWNER TO "postgres";


COMMENT ON TABLE "public"."client_accounts" IS 'Kunden-Datensätze mit Portal-Zugang, Vertragsdaten und Logo';



COMMENT ON COLUMN "public"."client_accounts"."id" IS 'Slug wie holidaycheck, giganetz — nicht Projekt-UUID';



COMMENT ON COLUMN "public"."client_accounts"."logo_url" IS 'Supabase Storage Path zum Kunden-Logo (Bucket: client-logos)';



CREATE OR REPLACE VIEW "public"."client_call_scores" WITH ("security_invoker"='off') AS
 SELECT "s"."id",
    "s"."employee_id",
    TRIM(BOTH FROM ((COALESCE("e"."first_name", ''::"text") || ' '::"text") || COALESCE("e"."last_name", ''::"text"))) AS "employee_name",
    "s"."project_id",
    "s"."skill",
    "s"."total_pct",
    "s"."sampled_date",
    "s"."kw",
    "s"."year",
    "s"."total_points",
    "s"."max_points",
    "s"."raw_points",
    "s"."compliance_failed"
   FROM ("public"."call_samples" "s"
     JOIN "public"."employees" "e" ON (("e"."id" = "s"."employee_id")))
  WHERE (("s"."status" = 'done'::"text") AND ("s"."project_id" = "public"."get_my_client_project_id"()));


ALTER VIEW "public"."client_call_scores" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."client_errors" (
    "sig" "text" NOT NULL,
    "kind" "text",
    "message" "text",
    "source" "text",
    "lineno" integer,
    "colno" integer,
    "area" "text",
    "stack" "text",
    "sample_url" "text",
    "user_agent" "text",
    "count" integer DEFAULT 1 NOT NULL,
    "first_seen" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_seen" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_user_id" "uuid",
    "last_user_name" "text",
    "resolved_at" timestamp with time zone
);


ALTER TABLE "public"."client_errors" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."client_meeting_briefs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text" NOT NULL,
    "generated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "generated_by" "uuid",
    "facts" "jsonb",
    "sections" "jsonb"
);


ALTER TABLE "public"."client_meeting_briefs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."contract_templates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "contract_kind" "text" DEFAULT 'unbefristet'::"text" NOT NULL,
    "language" "text" DEFAULT 'sq'::"text" NOT NULL,
    "body_html" "text",
    "reference_pdf_path" "text",
    "placeholders" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "contract_templates_contract_kind_check" CHECK (("contract_kind" = ANY (ARRAY['befristet'::"text", 'unbefristet'::"text"]))),
    CONSTRAINT "contract_templates_language_check" CHECK (("language" = ANY (ARRAY['sq'::"text", 'de'::"text", 'en'::"text"])))
);


ALTER TABLE "public"."contract_templates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cv_enrich_forms" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "sections" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "seq" integer DEFAULT 0 NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."cv_enrich_forms" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cv_enrich_invites" (
    "token" "text" DEFAULT "replace"(("gen_random_uuid"())::"text", '-'::"text", ''::"text") NOT NULL,
    "cv_id" "uuid" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("now"() + '30 days'::interval) NOT NULL,
    "used_at" timestamp with time zone,
    "form_id" "uuid",
    "reusable" boolean DEFAULT false NOT NULL,
    "opened_at" timestamp with time zone
);


ALTER TABLE "public"."cv_enrich_invites" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."daily_mailer" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "import_id" "uuid",
    "project_id" "text" NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "work_date" "date" NOT NULL,
    "mails" numeric,
    "log_hours" numeric,
    "raw" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."daily_mailer" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."daily_report_summaries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text" NOT NULL,
    "from_date" "date" NOT NULL,
    "to_date" "date" NOT NULL,
    "summary" "text",
    "model" "text",
    "generated_by" "uuid",
    "generated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."daily_report_summaries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."daily_reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "project_id" "text",
    "report_date" "date" NOT NULL,
    "body" "text" NOT NULL,
    "submitted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "late" boolean DEFAULT false NOT NULL,
    "char_count" integer,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."daily_reports" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."daily_tasks_done" (
    "task_key" "text" NOT NULL,
    "date" "date" NOT NULL,
    "done_by" "uuid",
    "done_by_name" "text",
    "done_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "assignee_user" "uuid",
    "project_id" "text",
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "session_id" "text",
    "session_writes" integer,
    "last_write_at" timestamp with time zone
);


ALTER TABLE "public"."daily_tasks_done" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dm_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "thread_id" "uuid" NOT NULL,
    "from_emp_id" "uuid" NOT NULL,
    "text_original" "text" NOT NULL,
    "lang_original" "text",
    "translations" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "sent_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."dm_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dm_participants" (
    "thread_id" "uuid" NOT NULL,
    "emp_id" "uuid" NOT NULL,
    "my_lang" "text" DEFAULT 'de'::"text" NOT NULL,
    "see_lang" "text" DEFAULT 'de'::"text" NOT NULL,
    "joined_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."dm_participants" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dm_reads" (
    "message_id" "uuid" NOT NULL,
    "emp_id" "uuid" NOT NULL,
    "read_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."dm_reads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dm_threads" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "is_group" boolean DEFAULT false NOT NULL,
    "name" "text",
    "dm_key" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."dm_threads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."employee_contracts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "template_id" "uuid",
    "field_values" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "generated_pdf_path" "text",
    "signed_pdf_path" "text",
    "sent_at" timestamp with time zone,
    "signed_at" timestamp with time zone,
    "applied_at" timestamp with time zone,
    "note" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "employee_contracts_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'sent'::"text", 'signed'::"text", 'archived'::"text", 'manual'::"text"])))
);


ALTER TABLE "public"."employee_contracts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."employee_documents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "doc_type" "text" NOT NULL,
    "storage_path" "text" NOT NULL,
    "original_name" "text",
    "size_bytes" bigint,
    "mime_type" "text" DEFAULT 'application/pdf'::"text",
    "uploaded_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "employee_documents_doc_type_check" CHECK (("doc_type" = ANY (ARRAY['contract'::"text", 'termination'::"text"])))
);


ALTER TABLE "public"."employee_documents" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."employees_client_view" WITH ("security_invoker"='false', "security_barrier"='true') AS
 SELECT "e"."id",
    "e"."first_name",
    "e"."last_name",
    "e"."position",
    "e"."project_skill" AS "skill",
    "e"."city",
    "e"."photo_url",
    "e"."language_level",
    "e"."project_id",
    "e"."status",
    "p"."color" AS "project_color"
   FROM ("public"."employees" "e"
     LEFT JOIN "public"."projects" "p" ON (("p"."id" = "e"."project_id")))
  WHERE (("e"."status" = ANY (ARRAY['active'::"text", 'training'::"text"])) AND ("e"."project_id" = "public"."get_my_client_project_id"()));


ALTER VIEW "public"."employees_client_view" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."employees_masked" AS
 SELECT "r"."id",
    "r"."first_name",
    "r"."last_name",
    "r"."email",
    "r"."phone",
    "r"."staff_number",
    "r"."role_keys",
    "r"."project_id",
    "r"."skill",
    "r"."target_role",
    "r"."status",
    "r"."source",
    "r"."cv_skills",
    "r"."hire_date",
    "r"."termination_date",
    "r"."location",
    "r"."photo_url",
    "r"."about_text",
    "r"."interests",
    "r"."notes",
    "r"."salary_type",
    "r"."hourly_rate",
    "r"."work_model",
    "r"."work_hours",
    "r"."shift_earliest",
    "r"."shift_latest",
    "r"."vacation_days",
    "r"."absences",
    "r"."audios",
    "r"."videos",
    "r"."warnings",
    "r"."project_assignments",
    "r"."allowed_shifts",
    "r"."bank",
    "r"."contract",
    "r"."extra",
    "r"."created_at",
    "r"."updated_at",
    "r"."abilities",
    "r"."bonuses",
    "r"."referrals",
    "r"."quality_ratings",
    "r"."hardware",
    "r"."position",
    "r"."city",
    "r"."id_number",
    "r"."project_skill",
    "r"."primary_skill",
    "r"."photo_color",
    "r"."fixed_salary",
    "r"."guaranteed_pct",
    "r"."deduct_missing",
    "r"."free_days_month",
    "r"."overtime_allowed",
    "r"."productive_pct",
    "r"."forecast_include",
    "r"."efficiency_override_pct",
    "r"."age",
    "r"."gender",
    "r"."education",
    "r"."education_level",
    "r"."experience_years",
    "r"."language_level",
    "r"."writing_level",
    "r"."languages_str",
    "r"."dream",
    "r"."hobbies",
    "r"."favorite_food",
    "r"."travel_wish",
    "r"."birthday",
    "r"."work_holidays",
    "r"."work_saturday",
    "r"."work_sunday",
    "r"."work_split",
    "r"."work_notes",
    "r"."training_id",
    "r"."staff_number_old",
    "r"."import_source",
    "r"."kpi_exempt",
    "r"."overhead_productive_pct",
    "r"."email_internal",
    "r"."salary_currency",
    "r"."status_changed_at"
   FROM ((( SELECT "e_1"."id",
            "e_1"."first_name",
            "e_1"."last_name",
            "e_1"."email",
            "e_1"."phone",
            "e_1"."staff_number",
            "e_1"."role_keys",
            "e_1"."project_id",
            "e_1"."skill",
            "e_1"."target_role",
            "e_1"."status",
            "e_1"."source",
            "e_1"."cv_skills",
            "e_1"."hire_date",
            "e_1"."termination_date",
            "e_1"."location",
            "e_1"."photo_url",
            "e_1"."about_text",
            "e_1"."interests",
            "e_1"."notes",
            "e_1"."salary_type",
            "e_1"."hourly_rate",
            "e_1"."work_model",
            "e_1"."work_hours",
            "e_1"."shift_earliest",
            "e_1"."shift_latest",
            "e_1"."vacation_days",
            "e_1"."absences",
            "e_1"."audios",
            "e_1"."videos",
            "e_1"."warnings",
            "e_1"."project_assignments",
            "e_1"."allowed_shifts",
            "e_1"."bank",
            "e_1"."contract",
            "e_1"."extra",
            "e_1"."created_at",
            "e_1"."updated_at",
            "e_1"."abilities",
            "e_1"."bonuses",
            "e_1"."referrals",
            "e_1"."quality_ratings",
            "e_1"."hardware",
            "e_1"."position",
            "e_1"."city",
            "e_1"."id_number",
            "e_1"."project_skill",
            "e_1"."primary_skill",
            "e_1"."photo_color",
            "e_1"."fixed_salary",
            "e_1"."guaranteed_pct",
            "e_1"."deduct_missing",
            "e_1"."free_days_month",
            "e_1"."overtime_allowed",
            "e_1"."productive_pct",
            "e_1"."forecast_include",
            "e_1"."efficiency_override_pct",
            "e_1"."age",
            "e_1"."gender",
            "e_1"."education",
            "e_1"."education_level",
            "e_1"."experience_years",
            "e_1"."language_level",
            "e_1"."writing_level",
            "e_1"."languages_str",
            "e_1"."dream",
            "e_1"."hobbies",
            "e_1"."favorite_food",
            "e_1"."travel_wish",
            "e_1"."birthday",
            "e_1"."work_holidays",
            "e_1"."work_saturday",
            "e_1"."work_sunday",
            "e_1"."work_split",
            "e_1"."work_notes",
            "e_1"."training_id",
            "e_1"."staff_number_old",
            "e_1"."import_source",
            "e_1"."kpi_exempt",
            "e_1"."overhead_productive_pct",
            "e_1"."email_internal",
            "e_1"."salary_currency",
            "e_1"."status_changed_at"
           FROM "public"."employees" "e_1"
          WHERE (("public"."perm_mode"("auth"."uid"(), 'emp'::"text") <> 'none'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'emp'::"text", "e_1"."project_id", NULL::"text"))) "e"
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN ("public"."is_management"() OR "public"."is_finance"()) THEN "to_jsonb"("e".*)
                    WHEN (("public"."perm"("auth"."uid"(), 'emp'::"text") ->> 'columns'::"text") = 'voll'::"text") THEN
                    CASE
                        WHEN "public"."is_protected_employee"("e"."id") THEN (((((("to_jsonb"("e".*) - 'fixed_salary'::"text") - 'hourly_rate'::"text") - 'salary_currency'::"text") - 'bank'::"text") - 'contract'::"text") - 'id_number'::"text")
                        WHEN (("public"."perm"("auth"."uid"(), 'emp'::"text") ->> 'salary'::"text") <> 'all'::"text") THEN ((("to_jsonb"("e".*) - 'fixed_salary'::"text") - 'hourly_rate'::"text") - 'salary_currency'::"text")
                        ELSE "to_jsonb"("e".*)
                    END
                    WHEN (("public"."perm"("auth"."uid"(), 'emp'::"text") ->> 'columns'::"text") = 'fuehrung'::"text") THEN
                    CASE
                        WHEN "public"."is_protected_employee"("e"."id") THEN (((((("to_jsonb"("e".*) - 'bank'::"text") - 'id_number'::"text") - 'fixed_salary'::"text") - 'hourly_rate'::"text") - 'salary_currency'::"text") - 'contract'::"text")
                        WHEN ((("public"."perm"("auth"."uid"(), 'emp'::"text") ->> 'salary'::"text") = 'all'::"text") AND ("public"."ai_position_rank"("e"."position") < "public"."perm_caller_rank"("auth"."uid"()))) THEN (("to_jsonb"("e".*) - 'bank'::"text") - 'id_number'::"text")
                        ELSE ((((("to_jsonb"("e".*) - 'bank'::"text") - 'id_number'::"text") - 'fixed_salary'::"text") - 'hourly_rate'::"text") - 'salary_currency'::"text")
                    END
                    WHEN (("public"."perm"("auth"."uid"(), 'emp'::"text") ->> 'columns'::"text") = 'personal'::"text") THEN ((("to_jsonb"("e".*) - 'fixed_salary'::"text") - 'hourly_rate'::"text") - 'salary_currency'::"text")
                    ELSE "jsonb_build_object"('contract', "jsonb_build_object"('start', (("to_jsonb"("e".*) -> 'contract'::"text") -> 'start'::"text")), 'writing_level', ("to_jsonb"("e".*) -> 'writing_level'::"text"), 'languages_str', ("to_jsonb"("e".*) -> 'languages_str'::"text"), 'target_role', ("to_jsonb"("e".*) -> 'target_role'::"text"), 'cv_skills', ("to_jsonb"("e".*) -> 'cv_skills'::"text"), 'education', ("to_jsonb"("e".*) -> 'education'::"text"), 'education_level', ("to_jsonb"("e".*) -> 'education_level'::"text"), 'experience_years', ("to_jsonb"("e".*) -> 'experience_years'::"text"), 'quality_ratings', ("to_jsonb"("e".*) -> 'quality_ratings'::"text"), 'hire_date', ("to_jsonb"("e".*) -> 'hire_date'::"text"), 'termination_date', ("to_jsonb"("e".*) -> 'termination_date'::"text"), 'project_assignments', ("to_jsonb"("e".*) -> 'project_assignments'::"text"), 'id', ("to_jsonb"("e".*) -> 'id'::"text"), 'first_name', ("to_jsonb"("e".*) -> 'first_name'::"text"), 'last_name', ("to_jsonb"("e".*) -> 'last_name'::"text"), 'position', ("to_jsonb"("e".*) -> 'position'::"text"), 'status', ("to_jsonb"("e".*) -> 'status'::"text"), 'project_id', ("to_jsonb"("e".*) -> 'project_id'::"text"), 'role_keys', ("to_jsonb"("e".*) -> 'role_keys'::"text"), 'photo_url', ("to_jsonb"("e".*) -> 'photo_url'::"text"), 'photo_color', ("to_jsonb"("e".*) -> 'photo_color'::"text"), 'email', ("to_jsonb"("e".*) -> 'email'::"text"), 'email_internal', ("to_jsonb"("e".*) -> 'email_internal'::"text"), 'phone', ("to_jsonb"("e".*) -> 'phone'::"text"), 'city', ("to_jsonb"("e".*) -> 'city'::"text"), 'location', ("to_jsonb"("e".*) -> 'location'::"text"), 'language_level', ("to_jsonb"("e".*) -> 'language_level'::"text"), 'skill', ("to_jsonb"("e".*) -> 'skill'::"text"), 'project_skill', ("to_jsonb"("e".*) -> 'project_skill'::"text"), 'primary_skill', ("to_jsonb"("e".*) -> 'primary_skill'::"text"), 'work_hours', ("to_jsonb"("e".*) -> 'work_hours'::"text"), 'work_model', ("to_jsonb"("e".*) -> 'work_model'::"text"), 'shift_earliest', ("to_jsonb"("e".*) -> 'shift_earliest'::"text"), 'shift_latest', ("to_jsonb"("e".*) -> 'shift_latest'::"text"), 'allowed_shifts', ("to_jsonb"("e".*) -> 'allowed_shifts'::"text"), 'work_saturday', ("to_jsonb"("e".*) -> 'work_saturday'::"text"), 'work_sunday', ("to_jsonb"("e".*) -> 'work_sunday'::"text"), 'work_holidays', ("to_jsonb"("e".*) -> 'work_holidays'::"text"), 'work_weekend', ("to_jsonb"("e".*) -> 'work_weekend'::"text"), 'work_split', ("to_jsonb"("e".*) -> 'work_split'::"text"), 'absences', ("to_jsonb"("e".*) -> 'absences'::"text"), 'vacation_days', ("to_jsonb"("e".*) -> 'vacation_days'::"text"), 'kpi_exempt', ("to_jsonb"("e".*) -> 'kpi_exempt'::"text"), 'created_at', ("to_jsonb"("e".*) -> 'created_at'::"text"))
                END AS "j") "m")
     CROSS JOIN LATERAL "jsonb_populate_record"(NULL::"public"."employees", "m"."j") "r"("id", "first_name", "last_name", "email", "phone", "staff_number", "role_keys", "project_id", "skill", "target_role", "status", "source", "cv_skills", "hire_date", "termination_date", "location", "photo_url", "about_text", "interests", "notes", "salary_type", "hourly_rate", "work_model", "work_hours", "shift_earliest", "shift_latest", "vacation_days", "absences", "audios", "videos", "warnings", "project_assignments", "allowed_shifts", "bank", "contract", "extra", "created_at", "updated_at", "abilities", "bonuses", "referrals", "quality_ratings", "hardware", "position", "city", "id_number", "project_skill", "primary_skill", "photo_color", "fixed_salary", "guaranteed_pct", "deduct_missing", "free_days_month", "overtime_allowed", "productive_pct", "forecast_include", "efficiency_override_pct", "age", "gender", "education", "education_level", "experience_years", "language_level", "writing_level", "languages_str", "dream", "hobbies", "favorite_food", "travel_wish", "birthday", "work_holidays", "work_saturday", "work_sunday", "work_split", "work_notes", "training_id", "staff_number_old", "import_source", "kpi_exempt", "overhead_productive_pct", "email_internal", "salary_currency", "status_changed_at"));


ALTER VIEW "public"."employees_masked" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."employees_masked_lite" WITH ("security_invoker"='true') AS
 SELECT "id",
    "first_name",
    "last_name",
    "email",
    "phone",
    "staff_number",
    "role_keys",
    "project_id",
    "skill",
    "target_role",
    "status",
    "source",
    "cv_skills",
    "hire_date",
    "termination_date",
    "location",
    "photo_url",
    "about_text",
    "interests",
    "notes",
    "salary_type",
    "hourly_rate",
    "work_model",
    "work_hours",
    "shift_earliest",
    "shift_latest",
    "vacation_days",
    "absences",
    "audios",
    "videos",
    "warnings",
    "project_assignments",
    "allowed_shifts",
    "bank",
    "contract",
    ("extra" - 'contract_file'::"text") AS "extra",
    "created_at",
    "updated_at",
    "abilities",
    "bonuses",
    "referrals",
    "quality_ratings",
    "hardware",
    "position",
    "city",
    "id_number",
    "project_skill",
    "primary_skill",
    "photo_color",
    "fixed_salary",
    "guaranteed_pct",
    "deduct_missing",
    "free_days_month",
    "overtime_allowed",
    "productive_pct",
    "forecast_include",
    "efficiency_override_pct",
    "age",
    "gender",
    "education",
    "education_level",
    "experience_years",
    "language_level",
    "writing_level",
    "languages_str",
    "dream",
    "hobbies",
    "favorite_food",
    "travel_wish",
    "birthday",
    "work_holidays",
    "work_saturday",
    "work_sunday",
    "work_split",
    "work_notes",
    "training_id",
    "staff_number_old",
    "import_source",
    "kpi_exempt",
    "overhead_productive_pct",
    "email_internal",
    "salary_currency",
    "status_changed_at"
   FROM "public"."employees_masked";


ALTER VIEW "public"."employees_masked_lite" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."employees_self" AS
 SELECT "id",
    "first_name",
    "last_name",
    "email",
    "phone",
    "staff_number",
    "role_keys",
    "project_id",
    "skill",
    "target_role",
    "status",
    "source",
    "cv_skills",
    "hire_date",
    "termination_date",
    "location",
    "photo_url",
    "about_text",
    "interests",
    "notes",
    "salary_type",
    "hourly_rate",
    "work_model",
    "work_hours",
    "shift_earliest",
    "shift_latest",
    "vacation_days",
    "absences",
    "audios",
    "videos",
    "warnings",
    "project_assignments",
    "allowed_shifts",
    "bank",
    "contract",
    "extra",
    "created_at",
    "updated_at",
    "abilities",
    "bonuses",
    "referrals",
    "quality_ratings",
    "hardware",
    "position",
    "city",
    "id_number",
    "project_skill",
    "primary_skill",
    "photo_color",
    "fixed_salary",
    "guaranteed_pct",
    "deduct_missing",
    "free_days_month",
    "overtime_allowed",
    "productive_pct",
    "forecast_include",
    "efficiency_override_pct",
    "age",
    "gender",
    "education",
    "education_level",
    "experience_years",
    "language_level",
    "writing_level",
    "languages_str",
    "dream",
    "hobbies",
    "favorite_food",
    "travel_wish",
    "birthday",
    "work_holidays",
    "work_saturday",
    "work_sunday",
    "work_split",
    "work_notes",
    "training_id",
    "staff_number_old",
    "import_source",
    "kpi_exempt",
    "overhead_productive_pct",
    "email_internal",
    "salary_currency",
    "status_changed_at"
   FROM "public"."employees"
  WHERE ("id" = "public"."perm_caller_emp_id"());


ALTER VIEW "public"."employees_self" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."employees_team_view" WITH ("security_invoker"='false', "security_barrier"='true') AS
 SELECT "id",
    "first_name",
    "last_name",
    "position",
    "role_keys",
    "project_id",
    "status",
    "photo_url",
    ("extra" ->> 'function'::"text") AS "function",
    ("extra" ->> 'project_skill'::"text") AS "project_skill",
    ("extra" ->> 'primary_skill'::"text") AS "primary_skill",
    ("extra" ->> 'photo_color'::"text") AS "photo_color"
   FROM "public"."employees"
  WHERE (("status" = ANY (ARRAY['active'::"text", 'training'::"text"])) AND ("project_id" = "public"."get_my_employee_project_id"()));


ALTER VIEW "public"."employees_team_view" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."feedback_answers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "session_id" "uuid" NOT NULL,
    "question_id" "uuid",
    "order_index" integer DEFAULT 0 NOT NULL,
    "section" "text",
    "prompt_snapshot" "text" NOT NULL,
    "type_snapshot" "text" NOT NULL,
    "answer_text" "text",
    "grade" integer,
    "followup_prompt_snapshot" "text",
    "followup_texts" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "feedback_answers_grade_check" CHECK ((("grade" >= 1) AND ("grade" <= 5))),
    CONSTRAINT "feedback_answers_type_snapshot_check" CHECK (("type_snapshot" = ANY (ARRAY['text'::"text", 'grade'::"text"])))
);


ALTER TABLE "public"."feedback_answers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."feedback_questions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "section" "text" NOT NULL,
    "order_index" integer DEFAULT 0 NOT NULL,
    "prompt" "text" NOT NULL,
    "type" "text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "followup_prompt" "text",
    "followup_show_if_grade_gte" integer,
    "followup_slots" integer,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "feedback_questions_followup_show_if_grade_gte_check" CHECK ((("followup_show_if_grade_gte" >= 1) AND ("followup_show_if_grade_gte" <= 5))),
    CONSTRAINT "feedback_questions_type_check" CHECK (("type" = ANY (ARRAY['text'::"text", 'grade'::"text"])))
);


ALTER TABLE "public"."feedback_questions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."feedback_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'scheduled'::"text" NOT NULL,
    "source" "text" DEFAULT 'random'::"text" NOT NULL,
    "scheduled_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "conducted_by" "uuid",
    "conducted_by_name" "text",
    "conducted_at" timestamp with time zone,
    "project_id" "text",
    "location" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "feedback_sessions_source_check" CHECK (("source" = ANY (ARRAY['random'::"text", 'manual'::"text"]))),
    CONSTRAINT "feedback_sessions_status_check" CHECK (("status" = ANY (ARRAY['scheduled'::"text", 'done'::"text", 'skipped'::"text"])))
);


ALTER TABLE "public"."feedback_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."forecast_actuals" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text",
    "month" "text",
    "revenue" numeric,
    "cost_personnel" numeric,
    "cost_other" numeric,
    "invoice_nr" "text",
    "notes" "text",
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."forecast_actuals" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."forecast_config" (
    "id" "text" DEFAULT 'singleton'::"text" NOT NULL,
    "gross_monthly_hours" numeric,
    "count_holidays_as_workday" boolean DEFAULT true,
    "deduct_absence_types" "text"[] DEFAULT ARRAY['vacation'::"text", 'sick'::"text", 'unpaid'::"text"],
    "default_efficiency_pct" numeric DEFAULT 100,
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."forecast_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."forecast_demand" (
    "project_id" "text" NOT NULL,
    "skill" "text" DEFAULT 'all'::"text" NOT NULL,
    "work_date" "date" NOT NULL,
    "ifc" "jsonb",
    "dfc" numeric,
    "updated_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."forecast_demand" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."import_aliases" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text" NOT NULL,
    "alias_name" "text" NOT NULL,
    "employee_id" "uuid",
    "created_by" "uuid",
    "created_by_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."import_aliases" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."interview_invites" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cv_id" "uuid" NOT NULL,
    "token" "text" NOT NULL,
    "participant_ids" "uuid"[] DEFAULT '{}'::"uuid"[] NOT NULL,
    "forms" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "booked_slot" timestamp with time zone,
    "booked_form" "text",
    "calendar_event_ids" "uuid"[] DEFAULT '{}'::"uuid"[],
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "opened_at" timestamp with time zone
);


ALTER TABLE "public"."interview_invites" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."kb_chunks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "document_id" "uuid" NOT NULL,
    "project_id" "text" NOT NULL,
    "ord" integer DEFAULT 0 NOT NULL,
    "section" "text",
    "page" integer,
    "content" "text" NOT NULL,
    "tsv" "tsvector" GENERATED ALWAYS AS ("to_tsvector"('"german"'::"regconfig", COALESCE("content", ''::"text"))) STORED,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."kb_chunks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."kb_documents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text" NOT NULL,
    "title" "text",
    "original_name" "text",
    "storage_path" "text",
    "mime_type" "text",
    "size_bytes" bigint,
    "doc_kind" "text",
    "summary" "text",
    "version" integer DEFAULT 1 NOT NULL,
    "supersedes" "uuid",
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "uploaded_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."kb_documents" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."kb_facts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text" NOT NULL,
    "topic" "text" NOT NULL,
    "zielgebiet" "text",
    "info_type" "text",
    "label" "text" NOT NULL,
    "value" "text" NOT NULL,
    "qualifier" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "source" "text" DEFAULT 'manual'::"text" NOT NULL,
    "source_document_id" "uuid",
    "source_locator" "text",
    "confidence" "text" DEFAULT 'confirmed'::"text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "valid_from" "date",
    "valid_to" "date",
    "first_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."kb_facts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."kb_queries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text" NOT NULL,
    "user_id" "uuid",
    "question" "text" NOT NULL,
    "known" boolean DEFAULT false NOT NULL,
    "had_rueckfrage" boolean DEFAULT false NOT NULL,
    "fact_count" integer DEFAULT 0 NOT NULL,
    "chunk_count" integer DEFAULT 0 NOT NULL,
    "answer" "text",
    "sources" "text"[],
    "helpful" boolean,
    "feedback_note" "text",
    "feedback_by" "uuid",
    "feedback_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "gap_topic" "text"
);


ALTER TABLE "public"."kb_queries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."kb_regions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "kind" "text",
    "aliases" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "members" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "source" "text" DEFAULT 'ki'::"text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "created_by" "uuid",
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."kb_regions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."lead_import_state" (
    "lead_id" "text" NOT NULL,
    "imported" boolean DEFAULT false NOT NULL,
    "imported_cv_id" "uuid",
    "status_review" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."lead_import_state" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."leader_nudge_prompts" (
    "key" "text" NOT NULL,
    "cond" "text" DEFAULT ''::"text" NOT NULL,
    "template" "text" NOT NULL,
    "prio" integer DEFAULT 1 NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."leader_nudge_prompts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."location_monthly" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "location_id" "text",
    "month" "text",
    "values" "jsonb" DEFAULT '{}'::"jsonb",
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."location_monthly" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."locations" (
    "id" "text" NOT NULL,
    "name" "text",
    "country" "text",
    "flag" "text",
    "color" "text",
    "address" "text",
    "active" boolean DEFAULT true,
    "capacity" "jsonb" DEFAULT '{}'::"jsonb",
    "costs_fixed" "jsonb" DEFAULT '{}'::"jsonb",
    "costs_custom" "jsonb" DEFAULT '[]'::"jsonb",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."locations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mail_attachments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "message_id" "uuid",
    "direction" "text",
    "name" "text",
    "size_bytes" bigint,
    "mime_type" "text",
    "storage_path" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."mail_attachments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mail_conversation_meta" (
    "conv_key" "text" NOT NULL,
    "tags" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "folder" "text",
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."mail_conversation_meta" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mail_folders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."mail_folders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mail_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "direction" "text" NOT NULL,
    "mailbox" "text",
    "cv_id" "uuid",
    "employee_id" "uuid",
    "from_address" "text",
    "to_address" "text",
    "subject" "text",
    "body_text" "text",
    "body_html" "text",
    "message_id" "text",
    "in_reply_to" "text",
    "status" "text",
    "error" "text",
    "occurred_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "filed_at" timestamp with time zone,
    "filed_by" "uuid",
    CONSTRAINT "mail_messages_direction_check" CHECK (("direction" = ANY (ARRAY['in'::"text", 'out'::"text"])))
);


ALTER TABLE "public"."mail_messages" OWNER TO "postgres";


COMMENT ON COLUMN "public"."mail_messages"."filed_at" IS 'Manuell "in die Akte" gelegt (NULL = nur im Postfach, nicht in der Personalakte).';



COMMENT ON COLUMN "public"."mail_messages"."filed_by" IS 'auth.uid() der Person, die die Mail in die Akte gelegt hat.';



CREATE TABLE IF NOT EXISTS "public"."mail_senders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "key" "text" NOT NULL,
    "label" "text" NOT NULL,
    "from_email" "text" DEFAULT ''::"text" NOT NULL,
    "from_name" "text" DEFAULT ''::"text" NOT NULL,
    "reply_to" "text",
    "provider" "text" DEFAULT 'resend'::"text" NOT NULL,
    "active" boolean DEFAULT false NOT NULL,
    "seq" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."mail_senders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mail_tags" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "color" "text" DEFAULT '#0F5661'::"text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."mail_tags" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mail_templates" (
    "key" "text" NOT NULL,
    "agent_key" "text",
    "subject" "text" NOT NULL,
    "body_html" "text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."mail_templates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."meeting_note_comments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "note_id" "uuid" NOT NULL,
    "item_id" "uuid",
    "project_id" "text" NOT NULL,
    "body" "text" NOT NULL,
    "author_name" "text",
    "created_by" "uuid",
    "read_at" timestamp with time zone,
    "read_by" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."meeting_note_comments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."meeting_note_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "note_id" "uuid",
    "project_id" "text" NOT NULL,
    "skill" "text",
    "text" "text" NOT NULL,
    "importance" "text" DEFAULT 'green'::"text" NOT NULL,
    "done" boolean DEFAULT false NOT NULL,
    "done_at" timestamp with time zone,
    "created_year" integer,
    "created_kw" integer,
    "done_year" integer,
    "done_kw" integer,
    "seq" integer DEFAULT 0 NOT NULL,
    "created_by" "uuid",
    "created_by_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "meeting_note_items_importance_check" CHECK (("importance" = ANY (ARRAY['green'::"text", 'amber'::"text", 'red'::"text"])))
);


ALTER TABLE "public"."meeting_note_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."meeting_notes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text" NOT NULL,
    "skill" "text",
    "meeting_date" "date" DEFAULT (("now"() AT TIME ZONE 'Europe/Berlin'::"text"))::"date" NOT NULL,
    "title" "text",
    "body" "text" DEFAULT ''::"text" NOT NULL,
    "created_by" "uuid",
    "created_by_name" "text",
    "updated_by_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."meeting_notes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mgmt_call_access" (
    "user_id" "uuid" NOT NULL,
    "added_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."mgmt_call_access" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mgmt_call_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "call_id" "uuid",
    "bereich" "text",
    "topic" "text",
    "text" "text" NOT NULL,
    "owner" "text",
    "due_date" "date",
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "done_at" timestamp with time zone,
    "carried_from_call_id" "uuid",
    "seq" integer DEFAULT 0 NOT NULL,
    "created_by" "uuid",
    "created_by_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "target_n" numeric,
    "actual_n" numeric,
    "progress_note" "text",
    "carried_from_item_id" "uuid",
    "owner_employee_id" "uuid"
);


ALTER TABLE "public"."mgmt_call_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mgmt_calls" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "call_date" "date" NOT NULL,
    "title" "text",
    "body" "text",
    "created_by" "uuid",
    "created_by_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "summary" "text"
);


ALTER TABLE "public"."mgmt_calls" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mgmt_task_out" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "item_id" "uuid",
    "assignee_user" "uuid" NOT NULL,
    "text" "text" NOT NULL,
    "context" "text",
    "due_date" "date",
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "done_at" timestamp with time zone,
    "done_by" "uuid",
    "created_by" "uuid",
    "created_by_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."mgmt_task_out" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notify_prefs" (
    "user_id" "uuid" NOT NULL,
    "channel" "text" DEFAULT 'slack'::"text" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notify_prefs_channel_check" CHECK (("channel" = ANY (ARRAY['slack'::"text", 'cliq'::"text", 'none'::"text"])))
);


ALTER TABLE "public"."notify_prefs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."org_nodes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text",
    "parent_id" "uuid",
    "title" "text",
    "subtitle" "text",
    "color" "text",
    "skill" "text",
    "employees" "jsonb" DEFAULT '[]'::"jsonb",
    "seq" integer,
    "auto_built" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."org_nodes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."partner_agents" (
    "project_id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "color" "text" DEFAULT '#0F5661'::"text" NOT NULL,
    "avatar_url" "text",
    "face_key" "text",
    "greeting" "text",
    "character" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid"
);


ALTER TABLE "public"."partner_agents" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."payroll_inputs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "emp_id" "uuid",
    "month" "text",
    "referral_bonus" numeric,
    "target_bonus" numeric,
    "special_bonus" numeric,
    "deduction_tax" numeric,
    "deduction_social" numeric,
    "deduction_other" numeric,
    "overtime_hours" numeric,
    "saturday_hours" numeric,
    "sunday_hours" numeric,
    "holiday_hours" numeric,
    "night_hours" numeric,
    "notes" "text",
    "deduction_notes" "text",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "total_worked_hours" numeric,
    "surcharge_source" "text"
);


ALTER TABLE "public"."payroll_inputs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."payslips" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "month" "text" NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "first_name" "text",
    "last_name" "text",
    "staff_number" "text",
    "position" "text",
    "location" "text",
    "project_id" "text",
    "email" "text",
    "hourly_rate" numeric,
    "work_hours" numeric,
    "work_model" "text",
    "contract_start" "date",
    "work_days" integer,
    "hours_per_day" numeric,
    "gross_hours" numeric,
    "base" numeric,
    "referral_bonus" numeric,
    "target_bonus" numeric,
    "special_bonus" numeric,
    "total_bonuses" numeric,
    "gross" numeric,
    "deduction_tax" numeric,
    "deduction_social" numeric,
    "deduction_other" numeric,
    "total_deductions" numeric,
    "net" numeric,
    "bonus_notes" "text",
    "deduction_notes" "text",
    "confirmed_at" timestamp with time zone,
    "paid_at" timestamp with time zone,
    "payment_date" "date",
    "payment_method" "text",
    "calc_detail" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "fixed_salary" numeric,
    "soll_days" numeric
);


ALTER TABLE "public"."payslips" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."permission_areas" (
    "key" "text" NOT NULL,
    "label" "text" NOT NULL,
    "seq" integer NOT NULL,
    "axes" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "menu_keys" "text"[] DEFAULT '{}'::"text"[] NOT NULL
);


ALTER TABLE "public"."permission_areas" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."position_config_client_view" WITH ("security_invoker"='false', "security_barrier"='true') AS
 SELECT "key",
    "value"
   FROM "public"."app_config"
  WHERE ("key" = ANY (ARRAY['jsr_overhead_positions_v1'::"text", 'jsr_company_positions_v1'::"text"]));


ALTER VIEW "public"."position_config_client_view" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."presentation_comments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "presentation_id" "uuid" NOT NULL,
    "project_id" "text" NOT NULL,
    "slide" "text",
    "anchor" "text",
    "severity" "text" DEFAULT 'black'::"text" NOT NULL,
    "body" "text" NOT NULL,
    "author_name" "text",
    "created_by" "uuid",
    "read_at" timestamp with time zone,
    "read_by" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "presentation_comments_severity_check" CHECK (("severity" = ANY (ARRAY['red'::"text", 'green'::"text", 'amber'::"text", 'black'::"text"])))
);


ALTER TABLE "public"."presentation_comments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."presentation_templates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "layout_key" "text" DEFAULT 'default'::"text" NOT NULL,
    "orientation" "text" DEFAULT 'landscape'::"text" NOT NULL,
    "project_id" "text",
    "slots" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "our_logo_path" "text",
    "customer_logo_path" "text",
    "contact_name" "text",
    "contact_email" "text",
    "contact_phone" "text",
    "created_by" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "presentation_templates_orient_chk" CHECK (("orientation" = ANY (ARRAY['landscape'::"text", 'portrait'::"text"])))
);


ALTER TABLE "public"."presentation_templates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."presentations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "template_id" "uuid",
    "project_id" "text" NOT NULL,
    "skill" "text",
    "period_type" "text" NOT NULL,
    "period_year" integer NOT NULL,
    "period_no" integer NOT NULL,
    "title" "text",
    "data" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "public_token" "text",
    "published" boolean DEFAULT false NOT NULL,
    "expires_at" timestamp with time zone,
    "created_by" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "kind" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "presentations_period_chk" CHECK (("period_type" = ANY (ARRAY['kw'::"text", 'month'::"text"])))
);


ALTER TABLE "public"."presentations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."project_skill_profiles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text",
    "skill_key" "text",
    "label" "text",
    "seq" integer
);


ALTER TABLE "public"."project_skill_profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."project_skills" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text",
    "key" "text",
    "label" "text",
    "rate" numeric,
    "rate_training" numeric,
    "seq" integer,
    "billing_type" "text",
    "minute_rate" numeric,
    "case_price" numeric,
    "case_aht_sec" numeric,
    "cpo_amount" numeric,
    "cpo_per_hour" numeric,
    "flat_per_agent" numeric,
    "productive_hours" numeric,
    "efficiency_pct" numeric,
    "training_mode" "text",
    "training_flat" numeric
);


ALTER TABLE "public"."project_skills" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."project_trainings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text",
    "tkey" "text",
    "name" "text",
    "weeks" integer,
    "seq" integer
);


ALTER TABLE "public"."project_trainings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."reminder_schedule" (
    "reminder_key" "text" NOT NULL,
    "user_id" "uuid",
    "active" boolean DEFAULT true NOT NULL,
    "hours" integer[] DEFAULT '{8}'::integer[] NOT NULL,
    "cadence" "text" DEFAULT 'daily'::"text" NOT NULL,
    "weekday" integer,
    "month_days" integer[],
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."reminder_schedule" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rk_monthly" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "location_id" "text",
    "month" "text",
    "values" "jsonb" DEFAULT '{}'::"jsonb",
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."rk_monthly" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rk_overhead" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "location_id" "text",
    "role" "text",
    "custom_label" "text",
    "emp_id" "uuid",
    "seq" integer,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."rk_overhead" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."role_permissions" (
    "role_key" "text" NOT NULL,
    "area_key" "text" NOT NULL,
    "visible" boolean DEFAULT false NOT NULL,
    "mode" "text" DEFAULT 'none'::"text" NOT NULL,
    "salary" "text" DEFAULT 'none'::"text" NOT NULL,
    "direction" "text" DEFAULT 'down'::"text" NOT NULL,
    "projects" "text" DEFAULT 'own'::"text" NOT NULL,
    "project_ids" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "skill" "text" DEFAULT 'all'::"text" NOT NULL,
    "columns" "text" DEFAULT 'operativ'::"text" NOT NULL
);


ALTER TABLE "public"."role_permissions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."roles_definitions" (
    "role_key" "text" NOT NULL,
    "label" "text" NOT NULL,
    "portals" "text"[] NOT NULL,
    "sort_order" integer
);


ALTER TABLE "public"."roles_definitions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sales_access" (
    "user_id" "uuid" NOT NULL,
    "added_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."sales_access" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sales_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lead_id" "uuid",
    "kind" "text" NOT NULL,
    "detail" "jsonb",
    "actor" "uuid",
    "occurred_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."sales_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sales_leads" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company" "text",
    "website" "text",
    "industry" "text",
    "contact_name" "text",
    "contact_email" "text",
    "contact_role" "text",
    "source" "text",
    "status" "text" DEFAULT 'new'::"text" NOT NULL,
    "research" "jsonb",
    "hook" "text",
    "notes" "text",
    "unsub_token" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "next_followup_at" timestamp with time zone,
    "last_activity_at" timestamp with time zone,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "stage" "text" DEFAULT 'erstansprache'::"text" NOT NULL,
    "score" numeric,
    "company_size" integer,
    "growth" "text",
    "email_tier" "text",
    CONSTRAINT "sales_leads_source_check" CHECK (("source" = ANY (ARRAY['mail'::"text", 'list'::"text", 'apollo'::"text", 'manual'::"text"]))),
    CONSTRAINT "sales_leads_status_check" CHECK (("status" = ANY (ARRAY['new'::"text", 'researched'::"text", 'contacted'::"text", 'opened'::"text", 'replied'::"text", 'handover'::"text", 'won'::"text", 'lost'::"text", 'dead'::"text", 'suppressed'::"text"])))
);


ALTER TABLE "public"."sales_leads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sales_suppression" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "email" "text" NOT NULL,
    "reason" "text" NOT NULL,
    "lead_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."sales_suppression" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sales_templates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "key" "text" NOT NULL,
    "name" "text",
    "subject" "text",
    "body" "text",
    "ai_enrich" boolean DEFAULT false NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "stage" "text",
    "variant" integer DEFAULT 1 NOT NULL
);


ALTER TABLE "public"."sales_templates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sales_upload_maps" (
    "signature" "text" NOT NULL,
    "mapping" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "sample_headers" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."sales_upload_maps" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shift_checkins" (
    "project_id" "text" NOT NULL,
    "skill" "text" DEFAULT 'all'::"text" NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "work_date" "date" NOT NULL,
    "status" "text" NOT NULL,
    "arrival" time without time zone,
    "departure" time without time zone,
    "reason" "text",
    "source" "text" DEFAULT 'manual'::"text" NOT NULL,
    "confirmed_by" "uuid",
    "confirmed_by_name" "text",
    "confirmed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "departure_source" "text",
    CONSTRAINT "shift_checkins_depsrc_chk" CHECK ((("departure_source" IS NULL) OR ("departure_source" = ANY (ARRAY['auto'::"text", 'manual'::"text", 'timeclock'::"text"])))),
    CONSTRAINT "shift_checkins_source_chk" CHECK (("source" = ANY (ARRAY['manual'::"text", 'timeclock'::"text"]))),
    CONSTRAINT "shift_checkins_status_chk" CHECK (("status" = ANY (ARRAY['present'::"text", 'late'::"text", 'early'::"text", 'sick'::"text", 'no_show'::"text"])))
);


ALTER TABLE "public"."shift_checkins" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."shifts_client_view" WITH ("security_invoker"='false', "security_barrier"='true') AS
 SELECT "s"."project_id",
    "s"."skill",
    "s"."employee_id",
    "s"."work_date",
    "s"."shift_value",
    "s"."label",
    "p"."color" AS "project_color"
   FROM ("public"."shift_assignments" "s"
     LEFT JOIN "public"."projects" "p" ON (("p"."id" = "s"."project_id")))
  WHERE (("s"."project_id" = "public"."get_my_client_project_id"()) AND ("s"."shift_value" IS NOT NULL) AND (COALESCE((("s"."shift" ->> 'canceled'::"text"))::boolean, false) = false));


ALTER VIEW "public"."shifts_client_view" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."showcases" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text" NOT NULL,
    "title" "text",
    "note" "text",
    "cv_ids" "uuid"[] DEFAULT '{}'::"uuid"[] NOT NULL,
    "token" "text" DEFAULT "encode"("extensions"."gen_random_bytes"(24), 'hex'::"text") NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "visible_fields" "text"[] DEFAULT ARRAY['first_name'::"text", 'last_name'::"text", 'age'::"text", 'city'::"text", 'experience_years'::"text", 'language_level'::"text", 'writing_level'::"text", 'languages_str'::"text", 'photo_url'::"text", 'photo_color'::"text", 'hobbies'::"text", 'favorite_food'::"text"] NOT NULL
);


ALTER TABLE "public"."showcases" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."spaces" (
    "id" "text" NOT NULL,
    "location_id" "text",
    "name" "text",
    "description" "text",
    "sqm" numeric,
    "floors" "jsonb" DEFAULT '[]'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."spaces" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."system_findings" (
    "fkey" "text" NOT NULL,
    "category" "text" NOT NULL,
    "severity" "text" DEFAULT 'cosmetic'::"text" NOT NULL,
    "title" "text" NOT NULL,
    "evidence" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "first_seen" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_seen" timestamp with time zone DEFAULT "now"() NOT NULL,
    "resolved_at" timestamp with time zone,
    "notified_at" timestamp with time zone,
    "digested_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."system_findings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."task_assignments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "task_key" "text" NOT NULL,
    "project_id" "text",
    "active" boolean DEFAULT true NOT NULL,
    "cadence_override" "text",
    "note" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."task_assignments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."task_catalog" (
    "key" "text" NOT NULL,
    "seq" integer DEFAULT 0 NOT NULL,
    "owner" "text"[] NOT NULL,
    "title" "text" NOT NULL,
    "descr" "text",
    "view_key" "text",
    "count_key" "text",
    "cadence" "text",
    "window_weeks" integer[],
    "auto_key" "text",
    "nav" "jsonb",
    "active" boolean DEFAULT true NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "data_gated" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."task_catalog" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."task_snooze" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "task_key" "text" NOT NULL,
    "project_id" "text",
    "date" "date" NOT NULL,
    "snooze_until" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."task_snooze" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."task_takeover" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "task_key" "text" NOT NULL,
    "project_id" "text",
    "date" "date" NOT NULL,
    "orig_assignee" "uuid",
    "taken_over_by" "uuid" NOT NULL,
    "taken_over_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."task_takeover" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."time_pin_attempts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "attempted_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."time_pin_attempts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."time_pins" (
    "emp_id" "uuid" NOT NULL,
    "code" "text",
    "changed" "date",
    "failed_attempts" integer DEFAULT 0,
    "locked_until" timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."time_pins" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."time_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "emp_id" "uuid",
    "session_date" "date",
    "clock_in" "text",
    "clock_out" "text",
    "hours" numeric,
    "hours_gross" numeric,
    "pauses" "jsonb" DEFAULT '[]'::"jsonb",
    "smokes" "jsonb" DEFAULT '[]'::"jsonb",
    "pause_active" "text",
    "smoke_active" "text",
    "pause_total" integer,
    "smoke_total" integer,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."time_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."training_plans" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text",
    "name" "text",
    "start_date" "date",
    "end_date" "date",
    "planned_count" integer,
    "mode" "text",
    "skill_focus" "text",
    "primary_skill" "text",
    "confirmed_ids" "jsonb" DEFAULT '[]'::"jsonb",
    "avg_salary" numeric,
    "status" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "active_date" "date"
);


ALTER TABLE "public"."training_plans" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."upload_project_owner" (
    "project_id" "text" NOT NULL,
    "responsible_user" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid"
);


ALTER TABLE "public"."upload_project_owner" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."upload_schedule" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "text" NOT NULL,
    "source_type" "text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "cadence" "text" DEFAULT 'weekly_retro'::"text" NOT NULL,
    "due_weekday" integer,
    "due_day" integer,
    "grace_days" integer DEFAULT 1 NOT NULL,
    "responsible_user" "uuid",
    "note" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid",
    CONSTRAINT "upload_schedule_cadence_check" CHECK (("cadence" = ANY (ARRAY['daily'::"text", 'weekly_retro'::"text", 'weekly_progressive'::"text", 'monthly'::"text"]))),
    CONSTRAINT "upload_schedule_due_day_check" CHECK ((("due_day" >= 1) AND ("due_day" <= 31))),
    CONSTRAINT "upload_schedule_due_weekday_check" CHECK ((("due_weekday" >= 1) AND ("due_weekday" <= 7))),
    CONSTRAINT "upload_schedule_grace_days_check" CHECK (("grace_days" >= 0))
);


ALTER TABLE "public"."upload_schedule" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."usage_digests" (
    "day" "date" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "user_name" "text",
    "summary" "text",
    "metrics" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."usage_digests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_permissions" (
    "user_id" "uuid" NOT NULL,
    "area_key" "text" NOT NULL,
    "visible" boolean DEFAULT false NOT NULL,
    "mode" "text" DEFAULT 'none'::"text" NOT NULL,
    "salary" "text" DEFAULT 'none'::"text" NOT NULL,
    "direction" "text" DEFAULT 'down'::"text" NOT NULL,
    "projects" "text" DEFAULT 'own'::"text" NOT NULL,
    "project_ids" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "skill" "text" DEFAULT 'all'::"text" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "columns" "text"
);


ALTER TABLE "public"."user_permissions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_prefs" (
    "user_id" "uuid" NOT NULL,
    "key" "text" NOT NULL,
    "value" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."user_prefs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_sessions" (
    "session_id" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "user_name" "text",
    "started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_seen" timestamp with time zone DEFAULT "now"() NOT NULL,
    "ping_count" integer DEFAULT 1 NOT NULL,
    "view_key" "text",
    "user_agent" "text"
);


ALTER TABLE "public"."user_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vacation_accounts" (
    "employee_id" "uuid" NOT NULL,
    "year" integer NOT NULL,
    "carry_in_days" numeric DEFAULT 0 NOT NULL,
    "carry_expires_on" "date",
    "note" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "vacation_accounts_year_chk" CHECK ((("year" >= 2020) AND ("year" <= 2100)))
);


ALTER TABLE "public"."vacation_accounts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vacation_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "employee_name" "text",
    "from_date" "date" NOT NULL,
    "to_date" "date" NOT NULL,
    "type" "text" DEFAULT 'vacation'::"text" NOT NULL,
    "days" numeric DEFAULT 0 NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "note" "text",
    "reject_reason" "text",
    "approved_by" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "counter_proposal" "jsonb",
    CONSTRAINT "vacation_requests_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text", 'counter'::"text"]))),
    CONSTRAINT "vacation_requests_type_check" CHECK (("type" = ANY (ARRAY['vacation'::"text", 'special'::"text", 'unpaid'::"text"])))
);


ALTER TABLE "public"."vacation_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vorort_attempts" (
    "id" bigint NOT NULL,
    "at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."vorort_attempts" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."vorort_attempts_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."vorort_attempts_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."vorort_attempts_id_seq" OWNED BY "public"."vorort_attempts"."id";



CREATE TABLE IF NOT EXISTS "public"."wheel_budgets" (
    "month" "text" NOT NULL,
    "amount" numeric,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."wheel_budgets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."wheel_specials" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "label" "text",
    "start_date" "date",
    "end_date" "date",
    "total_amount" numeric,
    "tranche_amount" numeric,
    "tranche_count" integer,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."wheel_specials" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."wheel_spins" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "emp_id" "uuid",
    "spin_date" "date",
    "amount" numeric,
    "source" "text",
    "special_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."wheel_spins" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."windsor_leads" (
    "id" "text" NOT NULL,
    "vor-_und_nachname" "text",
    "__telefonnummer__" "text",
    "__sprichst_du_deutsch__" "text",
    "__hast_du_erfahrung_im_call_center__" "text",
    "__arbeitszeit_verfügbar__" "text",
    "__wann_kannst_du_anfangen__" "text",
    "in_welchen_" "text",
    "created_time" timestamp with time zone,
    "campaign" "text",
    "ad_name" "text",
    "form_id" "text",
    "imported" boolean DEFAULT false NOT NULL,
    "imported_cv_id" "uuid",
    "status_review" "text",
    "inserted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "email" "text"
);


ALTER TABLE "public"."windsor_leads" OWNER TO "postgres";


ALTER TABLE ONLY "public"."agent_conversations" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."agent_conversations_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."agent_escalations" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."agent_escalations_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."agent_insights" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."agent_insights_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."agent_observations" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."agent_observations_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."vorort_attempts" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."vorort_attempts_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."activity_log"
    ADD CONSTRAINT "activity_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."agent_action_log"
    ADD CONSTRAINT "agent_action_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."agent_actions"
    ADD CONSTRAINT "agent_actions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."agent_checks"
    ADD CONSTRAINT "agent_checks_pkey" PRIMARY KEY ("agent_key");



ALTER TABLE ONLY "public"."agent_conversations"
    ADD CONSTRAINT "agent_conversations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."agent_digests"
    ADD CONSTRAINT "agent_digests_pkey" PRIMARY KEY ("day", "agent_key");



ALTER TABLE ONLY "public"."agent_escalations"
    ADD CONSTRAINT "agent_escalations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."agent_handoffs"
    ADD CONSTRAINT "agent_handoffs_day_topic_key" UNIQUE ("day", "topic");



ALTER TABLE ONLY "public"."agent_handoffs"
    ADD CONSTRAINT "agent_handoffs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."agent_insights"
    ADD CONSTRAINT "agent_insights_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."agent_insights"
    ADD CONSTRAINT "agent_insights_user_id_day_okey_key" UNIQUE ("user_id", "day", "okey");



ALTER TABLE ONLY "public"."agent_observations"
    ADD CONSTRAINT "agent_observations_day_okey_key" UNIQUE ("day", "okey");



ALTER TABLE ONLY "public"."agent_observations"
    ADD CONSTRAINT "agent_observations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."agent_prefs"
    ADD CONSTRAINT "agent_prefs_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."ai_access_prefs"
    ADD CONSTRAINT "ai_access_prefs_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."ai_agents"
    ADD CONSTRAINT "ai_agents_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."app_config"
    ADD CONSTRAINT "app_config_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."app_users"
    ADD CONSTRAINT "app_users_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."applicant_messages"
    ADD CONSTRAINT "applicant_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."assistant_gaps"
    ADD CONSTRAINT "assistant_gaps_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."calendar_events"
    ADD CONSTRAINT "calendar_events_auto_key_key" UNIQUE ("auto_key");



ALTER TABLE ONLY "public"."calendar_events"
    ADD CONSTRAINT "calendar_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."calendar_overrides"
    ADD CONSTRAINT "calendar_overrides_event_id_occurrence_date_key" UNIQUE ("event_id", "occurrence_date");



ALTER TABLE ONLY "public"."calendar_overrides"
    ADD CONSTRAINT "calendar_overrides_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."call_criteria"
    ADD CONSTRAINT "call_criteria_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."call_samples"
    ADD CONSTRAINT "call_samples_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."call_score_config"
    ADD CONSTRAINT "call_score_config_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."call_scores"
    ADD CONSTRAINT "call_scores_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chat_flags"
    ADD CONSTRAINT "chat_flags_message_id_key" UNIQUE ("message_id");



ALTER TABLE ONLY "public"."chat_flags"
    ADD CONSTRAINT "chat_flags_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."clara_handovers"
    ADD CONSTRAINT "clara_handovers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."clara_rejections"
    ADD CONSTRAINT "clara_rejections_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."client_accounts"
    ADD CONSTRAINT "client_accounts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."client_errors"
    ADD CONSTRAINT "client_errors_pkey" PRIMARY KEY ("sig");



ALTER TABLE ONLY "public"."client_meeting_briefs"
    ADD CONSTRAINT "client_meeting_briefs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."contract_templates"
    ADD CONSTRAINT "contract_templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cv_enrich_forms"
    ADD CONSTRAINT "cv_enrich_forms_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cv_enrich_invites"
    ADD CONSTRAINT "cv_enrich_invites_pkey" PRIMARY KEY ("token");



ALTER TABLE ONLY "public"."cvs"
    ADD CONSTRAINT "cvs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."daily_hours"
    ADD CONSTRAINT "daily_hours_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."daily_mailer"
    ADD CONSTRAINT "daily_mailer_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."daily_report_summaries"
    ADD CONSTRAINT "daily_report_summaries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."daily_reports"
    ADD CONSTRAINT "daily_reports_employee_id_report_date_key" UNIQUE ("employee_id", "report_date");



ALTER TABLE ONLY "public"."daily_reports"
    ADD CONSTRAINT "daily_reports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."daily_tasks_done"
    ADD CONSTRAINT "daily_tasks_done_instance_uniq" UNIQUE NULLS NOT DISTINCT ("task_key", "date", "assignee_user", "project_id");



ALTER TABLE ONLY "public"."daily_tasks_done"
    ADD CONSTRAINT "daily_tasks_done_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."data_imports"
    ADD CONSTRAINT "data_imports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dm_messages"
    ADD CONSTRAINT "dm_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dm_participants"
    ADD CONSTRAINT "dm_participants_pkey" PRIMARY KEY ("thread_id", "emp_id");



ALTER TABLE ONLY "public"."dm_reads"
    ADD CONSTRAINT "dm_reads_pkey" PRIMARY KEY ("message_id", "emp_id");



ALTER TABLE ONLY "public"."dm_threads"
    ADD CONSTRAINT "dm_threads_dm_key_key" UNIQUE ("dm_key");



ALTER TABLE ONLY "public"."dm_threads"
    ADD CONSTRAINT "dm_threads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."employee_contracts"
    ADD CONSTRAINT "employee_contracts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."employee_documents"
    ADD CONSTRAINT "employee_documents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."employee_documents"
    ADD CONSTRAINT "employee_documents_storage_path_key" UNIQUE ("storage_path");



ALTER TABLE ONLY "public"."employees"
    ADD CONSTRAINT "employees_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."employees"
    ADD CONSTRAINT "employees_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."feedback_answers"
    ADD CONSTRAINT "feedback_answers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."feedback_questions"
    ADD CONSTRAINT "feedback_questions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."feedback_sessions"
    ADD CONSTRAINT "feedback_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."forecast_actuals"
    ADD CONSTRAINT "forecast_actuals_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."forecast_actuals"
    ADD CONSTRAINT "forecast_actuals_project_id_month_key" UNIQUE ("project_id", "month");



ALTER TABLE ONLY "public"."forecast_config"
    ADD CONSTRAINT "forecast_config_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."forecast_demand"
    ADD CONSTRAINT "forecast_demand_pkey" PRIMARY KEY ("project_id", "skill", "work_date");



ALTER TABLE ONLY "public"."import_aliases"
    ADD CONSTRAINT "import_aliases_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."interview_invites"
    ADD CONSTRAINT "interview_invites_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."interview_invites"
    ADD CONSTRAINT "interview_invites_token_key" UNIQUE ("token");



ALTER TABLE ONLY "public"."kb_chunks"
    ADD CONSTRAINT "kb_chunks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."kb_documents"
    ADD CONSTRAINT "kb_documents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."kb_documents"
    ADD CONSTRAINT "kb_documents_storage_path_key" UNIQUE ("storage_path");



ALTER TABLE ONLY "public"."kb_facts"
    ADD CONSTRAINT "kb_facts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."kb_queries"
    ADD CONSTRAINT "kb_queries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."kb_regions"
    ADD CONSTRAINT "kb_regions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."kpi_config"
    ADD CONSTRAINT "kpi_config_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."kpi_entries"
    ADD CONSTRAINT "kpi_entries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."kpi_project_entries"
    ADD CONSTRAINT "kpi_project_entries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."lead_import_state"
    ADD CONSTRAINT "lead_import_state_pkey" PRIMARY KEY ("lead_id");



ALTER TABLE ONLY "public"."leader_nudge_prompts"
    ADD CONSTRAINT "leader_nudge_prompts_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."location_monthly"
    ADD CONSTRAINT "location_monthly_location_id_month_key" UNIQUE ("location_id", "month");



ALTER TABLE ONLY "public"."location_monthly"
    ADD CONSTRAINT "location_monthly_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."locations"
    ADD CONSTRAINT "locations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mail_attachments"
    ADD CONSTRAINT "mail_attachments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mail_conversation_meta"
    ADD CONSTRAINT "mail_conversation_meta_pkey" PRIMARY KEY ("conv_key");



ALTER TABLE ONLY "public"."mail_folders"
    ADD CONSTRAINT "mail_folders_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."mail_folders"
    ADD CONSTRAINT "mail_folders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mail_messages"
    ADD CONSTRAINT "mail_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mail_senders"
    ADD CONSTRAINT "mail_senders_key_key" UNIQUE ("key");



ALTER TABLE ONLY "public"."mail_senders"
    ADD CONSTRAINT "mail_senders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mail_tags"
    ADD CONSTRAINT "mail_tags_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."mail_tags"
    ADD CONSTRAINT "mail_tags_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mail_templates"
    ADD CONSTRAINT "mail_templates_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."meeting_note_comments"
    ADD CONSTRAINT "meeting_note_comments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."meeting_note_items"
    ADD CONSTRAINT "meeting_note_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."meeting_notes"
    ADD CONSTRAINT "meeting_notes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mgmt_call_access"
    ADD CONSTRAINT "mgmt_call_access_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."mgmt_call_items"
    ADD CONSTRAINT "mgmt_call_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mgmt_calls"
    ADD CONSTRAINT "mgmt_calls_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mgmt_task_out"
    ADD CONSTRAINT "mgmt_task_out_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notify_prefs"
    ADD CONSTRAINT "notify_prefs_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."org_nodes"
    ADD CONSTRAINT "org_nodes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."partner_agents"
    ADD CONSTRAINT "partner_agents_pkey" PRIMARY KEY ("project_id");



ALTER TABLE ONLY "public"."payroll_inputs"
    ADD CONSTRAINT "payroll_inputs_emp_id_month_key" UNIQUE ("emp_id", "month");



ALTER TABLE ONLY "public"."payroll_inputs"
    ADD CONSTRAINT "payroll_inputs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payslips"
    ADD CONSTRAINT "payslips_employee_id_month_key" UNIQUE ("employee_id", "month");



ALTER TABLE ONLY "public"."payslips"
    ADD CONSTRAINT "payslips_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."permission_areas"
    ADD CONSTRAINT "permission_areas_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."presentation_comments"
    ADD CONSTRAINT "presentation_comments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."presentation_templates"
    ADD CONSTRAINT "presentation_templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."presentations"
    ADD CONSTRAINT "presentations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."presentations"
    ADD CONSTRAINT "presentations_public_token_key" UNIQUE ("public_token");



ALTER TABLE ONLY "public"."project_skill_profiles"
    ADD CONSTRAINT "project_skill_profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."project_skills"
    ADD CONSTRAINT "project_skills_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."project_skills"
    ADD CONSTRAINT "project_skills_project_id_key_key" UNIQUE ("project_id", "key");



ALTER TABLE ONLY "public"."project_trainings"
    ADD CONSTRAINT "project_trainings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."report_forecast"
    ADD CONSTRAINT "report_forecast_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."report_forecast"
    ADD CONSTRAINT "report_forecast_project_id_skill_year_kw_key" UNIQUE ("project_id", "skill", "year", "kw");



ALTER TABLE ONLY "public"."report_fte"
    ADD CONSTRAINT "report_fte_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."report_fte"
    ADD CONSTRAINT "report_fte_project_id_employee_id_key" UNIQUE ("project_id", "employee_id");



ALTER TABLE ONLY "public"."report_longterm"
    ADD CONSTRAINT "report_longterm_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."report_longterm"
    ADD CONSTRAINT "report_longterm_project_id_skill_key" UNIQUE ("project_id", "skill");



ALTER TABLE ONLY "public"."report_measures"
    ADD CONSTRAINT "report_measures_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rk_monthly"
    ADD CONSTRAINT "rk_monthly_location_id_month_key" UNIQUE ("location_id", "month");



ALTER TABLE ONLY "public"."rk_monthly"
    ADD CONSTRAINT "rk_monthly_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rk_overhead"
    ADD CONSTRAINT "rk_overhead_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."role_permissions"
    ADD CONSTRAINT "role_permissions_pkey" PRIMARY KEY ("role_key", "area_key");



ALTER TABLE ONLY "public"."roles_definitions"
    ADD CONSTRAINT "roles_definitions_pkey" PRIMARY KEY ("role_key");



ALTER TABLE ONLY "public"."sales_access"
    ADD CONSTRAINT "sales_access_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."sales_events"
    ADD CONSTRAINT "sales_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_leads"
    ADD CONSTRAINT "sales_leads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_suppression"
    ADD CONSTRAINT "sales_suppression_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."sales_suppression"
    ADD CONSTRAINT "sales_suppression_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_templates"
    ADD CONSTRAINT "sales_templates_key_key" UNIQUE ("key");



ALTER TABLE ONLY "public"."sales_templates"
    ADD CONSTRAINT "sales_templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_upload_maps"
    ADD CONSTRAINT "sales_upload_maps_pkey" PRIMARY KEY ("signature");



ALTER TABLE ONLY "public"."shift_assignments"
    ADD CONSTRAINT "shift_assignments_pkey" PRIMARY KEY ("project_id", "skill", "employee_id", "work_date");



ALTER TABLE ONLY "public"."shift_checkins"
    ADD CONSTRAINT "shift_checkins_pkey" PRIMARY KEY ("project_id", "skill", "employee_id", "work_date", "source");



ALTER TABLE ONLY "public"."showcases"
    ADD CONSTRAINT "showcases_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."showcases"
    ADD CONSTRAINT "showcases_token_key" UNIQUE ("token");



ALTER TABLE ONLY "public"."spaces"
    ADD CONSTRAINT "spaces_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."system_findings"
    ADD CONSTRAINT "system_findings_pkey" PRIMARY KEY ("fkey");



ALTER TABLE ONLY "public"."task_assignments"
    ADD CONSTRAINT "task_assignments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."task_assignments"
    ADD CONSTRAINT "task_assignments_uniq" UNIQUE NULLS NOT DISTINCT ("user_id", "task_key", "project_id");



ALTER TABLE ONLY "public"."task_catalog"
    ADD CONSTRAINT "task_catalog_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."task_snooze"
    ADD CONSTRAINT "task_snooze_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."task_snooze"
    ADD CONSTRAINT "task_snooze_uniq" UNIQUE NULLS NOT DISTINCT ("user_id", "task_key", "project_id", "date");



ALTER TABLE ONLY "public"."task_takeover"
    ADD CONSTRAINT "task_takeover_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."task_takeover"
    ADD CONSTRAINT "task_takeover_uniq" UNIQUE NULLS NOT DISTINCT ("task_key", "project_id", "date", "orig_assignee");



ALTER TABLE ONLY "public"."time_pin_attempts"
    ADD CONSTRAINT "time_pin_attempts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."time_pins"
    ADD CONSTRAINT "time_pins_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."time_pins"
    ADD CONSTRAINT "time_pins_pkey" PRIMARY KEY ("emp_id");



ALTER TABLE ONLY "public"."time_sessions"
    ADD CONSTRAINT "time_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."training_plans"
    ADD CONSTRAINT "training_plans_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."upload_project_owner"
    ADD CONSTRAINT "upload_project_owner_pkey" PRIMARY KEY ("project_id");



ALTER TABLE ONLY "public"."upload_schedule"
    ADD CONSTRAINT "upload_schedule_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."upload_schedule"
    ADD CONSTRAINT "upload_schedule_project_id_source_type_key" UNIQUE ("project_id", "source_type");



ALTER TABLE ONLY "public"."usage_digests"
    ADD CONSTRAINT "usage_digests_pkey" PRIMARY KEY ("day", "user_id");



ALTER TABLE ONLY "public"."user_permissions"
    ADD CONSTRAINT "user_permissions_pkey" PRIMARY KEY ("user_id", "area_key");



ALTER TABLE ONLY "public"."user_prefs"
    ADD CONSTRAINT "user_prefs_pkey" PRIMARY KEY ("user_id", "key");



ALTER TABLE ONLY "public"."user_sessions"
    ADD CONSTRAINT "user_sessions_pkey" PRIMARY KEY ("session_id");



ALTER TABLE ONLY "public"."vacation_accounts"
    ADD CONSTRAINT "vacation_accounts_pkey" PRIMARY KEY ("employee_id", "year");



ALTER TABLE ONLY "public"."vacation_requests"
    ADD CONSTRAINT "vacation_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."vorort_attempts"
    ADD CONSTRAINT "vorort_attempts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."weekly_calls"
    ADD CONSTRAINT "weekly_calls_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."weekly_gauges"
    ADD CONSTRAINT "weekly_gauges_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."weekly_hours_legacy"
    ADD CONSTRAINT "weekly_hours_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wheel_budgets"
    ADD CONSTRAINT "wheel_budgets_pkey" PRIMARY KEY ("month");



ALTER TABLE ONLY "public"."wheel_specials"
    ADD CONSTRAINT "wheel_specials_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wheel_spins"
    ADD CONSTRAINT "wheel_spins_emp_id_spin_date_key" UNIQUE ("emp_id", "spin_date");



ALTER TABLE ONLY "public"."wheel_spins"
    ADD CONSTRAINT "wheel_spins_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."windsor_leads"
    ADD CONSTRAINT "windsor_leads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."windsor_marketing"
    ADD CONSTRAINT "windsor_marketing_dsc_key" UNIQUE NULLS NOT DISTINCT ("datasource", "date", "campaign") DEFERRABLE INITIALLY DEFERRED;



CREATE INDEX "agent_conv_sess_idx" ON "public"."agent_conversations" USING "btree" ("agent_key", "user_id", "session_id", "created_at");



CREATE INDEX "agent_handoffs_day" ON "public"."agent_handoffs" USING "btree" ("day" DESC, "created_at" DESC);



CREATE INDEX "applicant_messages_created" ON "public"."applicant_messages" USING "btree" ("created_at" DESC);



CREATE INDEX "applicant_messages_cv" ON "public"."applicant_messages" USING "btree" ("cv_id");



CREATE UNIQUE INDEX "applicant_messages_jobfair_cv_uq" ON "public"."applicant_messages" USING "btree" ("cv_id") WHERE ("purpose" = 'jobfair'::"text");



CREATE UNIQUE INDEX "clara_handovers_one_open" ON "public"."clara_handovers" USING "btree" ("cv_id") WHERE ("resolved_at" IS NULL);



CREATE INDEX "clara_handovers_open_idx" ON "public"."clara_handovers" USING "btree" ("resolved_at") WHERE ("resolved_at" IS NULL);



CREATE INDEX "clara_rejections_cv_idx" ON "public"."clara_rejections" USING "btree" ("cv_id");



CREATE INDEX "clara_rejections_due_idx" ON "public"."clara_rejections" USING "btree" ("due_at") WHERE (("sent_at" IS NULL) AND ("cancelled_at" IS NULL));



CREATE INDEX "client_meeting_briefs_proj" ON "public"."client_meeting_briefs" USING "btree" ("project_id", "generated_at" DESC);



CREATE INDEX "cv_enrich_invites_cv" ON "public"."cv_enrich_invites" USING "btree" ("cv_id");



CREATE INDEX "feedback_answers_question" ON "public"."feedback_answers" USING "btree" ("question_id");



CREATE INDEX "feedback_answers_session" ON "public"."feedback_answers" USING "btree" ("session_id");



CREATE INDEX "feedback_questions_order" ON "public"."feedback_questions" USING "btree" ("active", "order_index");



CREATE INDEX "feedback_sessions_emp" ON "public"."feedback_sessions" USING "btree" ("employee_id", "scheduled_date");



CREATE INDEX "feedback_sessions_sched" ON "public"."feedback_sessions" USING "btree" ("scheduled_date", "status");



CREATE INDEX "idx_activity_action" ON "public"."activity_log" USING "btree" ("action");



CREATE INDEX "idx_activity_created" ON "public"."activity_log" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_activity_log_user_time" ON "public"."activity_log" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "idx_activity_user" ON "public"."activity_log" USING "btree" ("user_id");



CREATE INDEX "idx_agent_actions_key_at" ON "public"."agent_actions" USING "btree" ("agent_key", "at" DESC);



CREATE INDEX "idx_agent_conv_user" ON "public"."agent_conversations" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "idx_agent_esc_user" ON "public"."agent_escalations" USING "btree" ("user_id");



CREATE INDEX "idx_agent_insights_user" ON "public"."agent_insights" USING "btree" ("user_id", "dismissed_at", "seen_at");



CREATE INDEX "idx_agent_obs_day" ON "public"."agent_observations" USING "btree" ("day" DESC);



CREATE INDEX "idx_app_users_employee_id" ON "public"."app_users" USING "btree" ("employee_id");



CREATE INDEX "idx_calendar_events_proj" ON "public"."calendar_events" USING "btree" ("project_id");



CREATE INDEX "idx_calendar_events_start" ON "public"."calendar_events" USING "btree" ("start_date");



CREATE INDEX "idx_calendar_ovr_event" ON "public"."calendar_overrides" USING "btree" ("event_id", "occurrence_date");



CREATE INDEX "idx_call_criteria_lookup" ON "public"."call_criteria" USING "btree" ("project_id", "skill", "active", "order_index");



CREATE INDEX "idx_call_samples_emp" ON "public"."call_samples" USING "btree" ("employee_id", "sampled_date" DESC);



CREATE INDEX "idx_call_samples_period" ON "public"."call_samples" USING "btree" ("project_id", "skill", "year", "kw");



CREATE INDEX "idx_call_scores_sample" ON "public"."call_scores" USING "btree" ("sample_id");



CREATE INDEX "idx_chat_flags_created" ON "public"."chat_flags" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_checkin_emp_date" ON "public"."shift_checkins" USING "btree" ("employee_id", "work_date");



CREATE INDEX "idx_checkin_proj_date" ON "public"."shift_checkins" USING "btree" ("project_id", "skill", "work_date");



CREATE INDEX "idx_client_accounts_project_id" ON "public"."client_accounts" USING "btree" ("project_id");



CREATE INDEX "idx_client_errors_open" ON "public"."client_errors" USING "btree" ("resolved_at", "last_seen" DESC);



CREATE INDEX "idx_cvs_email" ON "public"."cvs" USING "btree" ("email");



CREATE UNIQUE INDEX "idx_cvs_email_unique" ON "public"."cvs" USING "btree" ("email") WHERE (("email" IS NOT NULL) AND ("email" <> ''::"text"));



CREATE UNIQUE INDEX "idx_cvs_phone_unique" ON "public"."cvs" USING "btree" ("phone") WHERE (("phone" IS NOT NULL) AND ("phone" <> ''::"text"));



CREATE INDEX "idx_cvs_project_id" ON "public"."cvs" USING "btree" ("project_id");



CREATE UNIQUE INDEX "idx_cvs_public_code" ON "public"."cvs" USING "btree" ("public_code") WHERE ("public_code" IS NOT NULL);



CREATE INDEX "idx_cvs_status" ON "public"."cvs" USING "btree" ("status");



CREATE INDEX "idx_daily_hours_scope" ON "public"."daily_hours" USING "btree" ("project_id", "work_date");



CREATE INDEX "idx_daily_mailer_scope" ON "public"."daily_mailer" USING "btree" ("project_id", "work_date");



CREATE INDEX "idx_daily_reports_emp_date" ON "public"."daily_reports" USING "btree" ("employee_id", "report_date");



CREATE INDEX "idx_daily_reports_proj_date" ON "public"."daily_reports" USING "btree" ("project_id", "report_date");



CREATE INDEX "idx_data_imports_scope" ON "public"."data_imports" USING "btree" ("project_id", "source_type", "year", "kw", "created_at" DESC);



CREATE INDEX "idx_dm_msg_thread" ON "public"."dm_messages" USING "btree" ("thread_id", "sent_at");



CREATE INDEX "idx_dm_part_emp" ON "public"."dm_participants" USING "btree" ("emp_id");



CREATE INDEX "idx_dm_reads_emp" ON "public"."dm_reads" USING "btree" ("emp_id");



CREATE INDEX "idx_drs_proj" ON "public"."daily_report_summaries" USING "btree" ("project_id", "from_date", "to_date");



CREATE INDEX "idx_employee_contracts_emp" ON "public"."employee_contracts" USING "btree" ("employee_id", "status");



CREATE INDEX "idx_employee_documents_employee_id" ON "public"."employee_documents" USING "btree" ("employee_id");



CREATE INDEX "idx_employees_email" ON "public"."employees" USING "btree" ("email");



CREATE INDEX "idx_employees_position" ON "public"."employees" USING "btree" ("position");



CREATE INDEX "idx_employees_project_id" ON "public"."employees" USING "btree" ("project_id");



CREATE INDEX "idx_employees_staff_number" ON "public"."employees" USING "btree" ("staff_number");



CREATE INDEX "idx_employees_staff_number_old" ON "public"."employees" USING "btree" ("staff_number_old");



CREATE INDEX "idx_employees_status" ON "public"."employees" USING "btree" ("status");



CREATE INDEX "idx_forecast_actuals_month" ON "public"."forecast_actuals" USING "btree" ("month");



CREATE INDEX "idx_forecast_actuals_project" ON "public"."forecast_actuals" USING "btree" ("project_id");



CREATE INDEX "idx_kpi_entries_import" ON "public"."kpi_entries" USING "btree" ("import_id");



CREATE INDEX "idx_kpi_project_entries_import" ON "public"."kpi_project_entries" USING "btree" ("import_id");



CREATE INDEX "idx_kpi_project_entries_lookup" ON "public"."kpi_project_entries" USING "btree" ("project_id", "year", "kw");



CREATE INDEX "idx_kpi_project_entries_month_lookup" ON "public"."kpi_project_entries" USING "btree" ("project_id", "year", "month") WHERE ("month" IS NOT NULL);



CREATE INDEX "idx_location_monthly_loc" ON "public"."location_monthly" USING "btree" ("location_id");



CREATE INDEX "idx_meeting_note_comments_note" ON "public"."meeting_note_comments" USING "btree" ("note_id", "created_at" DESC);



CREATE INDEX "idx_meeting_note_items_note" ON "public"."meeting_note_items" USING "btree" ("note_id");



CREATE INDEX "idx_meeting_note_items_scope" ON "public"."meeting_note_items" USING "btree" ("project_id", "done", "created_year", "created_kw");



CREATE INDEX "idx_meeting_notes_scope" ON "public"."meeting_notes" USING "btree" ("project_id", "meeting_date" DESC);



CREATE INDEX "idx_org_nodes_parent" ON "public"."org_nodes" USING "btree" ("parent_id");



CREATE INDEX "idx_org_nodes_project" ON "public"."org_nodes" USING "btree" ("project_id");



CREATE INDEX "idx_payroll_inputs_emp" ON "public"."payroll_inputs" USING "btree" ("emp_id");



CREATE INDEX "idx_payroll_inputs_month" ON "public"."payroll_inputs" USING "btree" ("month");



CREATE INDEX "idx_payslips_employee_id" ON "public"."payslips" USING "btree" ("employee_id");



CREATE INDEX "idx_payslips_month" ON "public"."payslips" USING "btree" ("month");



CREATE INDEX "idx_payslips_status" ON "public"."payslips" USING "btree" ("status");



CREATE INDEX "idx_pres_comments_pres" ON "public"."presentation_comments" USING "btree" ("presentation_id");



CREATE INDEX "idx_pres_comments_proj" ON "public"."presentation_comments" USING "btree" ("project_id", "created_at" DESC);



CREATE INDEX "idx_presentations_period" ON "public"."presentations" USING "btree" ("project_id", "period_year", "period_no");



CREATE INDEX "idx_presentations_token" ON "public"."presentations" USING "btree" ("public_token");



CREATE INDEX "idx_report_forecast_lookup" ON "public"."report_forecast" USING "btree" ("project_id", "skill", "year", "kw");



CREATE INDEX "idx_report_measures_scope" ON "public"."report_measures" USING "btree" ("project_id", "skill", "status", "created_year", "created_kw");



CREATE INDEX "idx_rk_monthly_loc" ON "public"."rk_monthly" USING "btree" ("location_id");



CREATE INDEX "idx_rk_overhead_loc" ON "public"."rk_overhead" USING "btree" ("location_id");



CREATE INDEX "idx_shift_emp_date" ON "public"."shift_assignments" USING "btree" ("employee_id", "work_date");



CREATE INDEX "idx_shift_proj_date" ON "public"."shift_assignments" USING "btree" ("project_id", "skill", "work_date");



CREATE INDEX "idx_showcases_project_id" ON "public"."showcases" USING "btree" ("project_id");



CREATE INDEX "idx_showcases_token" ON "public"."showcases" USING "btree" ("token");



CREATE INDEX "idx_spaces_loc" ON "public"."spaces" USING "btree" ("location_id");



CREATE INDEX "idx_time_pin_attempts_at" ON "public"."time_pin_attempts" USING "btree" ("attempted_at");



CREATE INDEX "idx_time_sessions_emp_date" ON "public"."time_sessions" USING "btree" ("emp_id", "session_date");



CREATE INDEX "idx_training_plans_project" ON "public"."training_plans" USING "btree" ("project_id");



CREATE INDEX "idx_user_sessions_user" ON "public"."user_sessions" USING "btree" ("user_id", "started_at" DESC);



CREATE INDEX "idx_vacation_accounts_year" ON "public"."vacation_accounts" USING "btree" ("year");



CREATE INDEX "idx_vacreq_employee" ON "public"."vacation_requests" USING "btree" ("employee_id");



CREATE INDEX "idx_vacreq_status" ON "public"."vacation_requests" USING "btree" ("status");



CREATE INDEX "idx_vorort_attempts_at" ON "public"."vorort_attempts" USING "btree" ("at");



CREATE INDEX "idx_wheel_spins_date" ON "public"."wheel_spins" USING "btree" ("spin_date");



CREATE INDEX "idx_wheel_spins_emp" ON "public"."wheel_spins" USING "btree" ("emp_id");



CREATE INDEX "idx_windsor_leads_pending" ON "public"."windsor_leads" USING "btree" ("inserted_at") WHERE ("imported" = false);



CREATE INDEX "idx_windsor_marketing_scope" ON "public"."windsor_marketing" USING "btree" ("datasource", "date");



CREATE INDEX "kb_chunks_document_idx" ON "public"."kb_chunks" USING "btree" ("document_id");



CREATE INDEX "kb_chunks_project_idx" ON "public"."kb_chunks" USING "btree" ("project_id");



CREATE INDEX "kb_chunks_tsv_idx" ON "public"."kb_chunks" USING "gin" ("tsv");



CREATE INDEX "kb_documents_project_idx" ON "public"."kb_documents" USING "btree" ("project_id");



CREATE INDEX "kb_documents_status_idx" ON "public"."kb_documents" USING "btree" ("project_id", "status");



CREATE INDEX "kb_facts_project_idx" ON "public"."kb_facts" USING "btree" ("project_id", "status");



CREATE INDEX "kb_facts_topic_idx" ON "public"."kb_facts" USING "btree" ("project_id", "topic");



CREATE INDEX "kb_facts_zielgebiet_idx" ON "public"."kb_facts" USING "btree" ("project_id", "zielgebiet");



CREATE INDEX "kb_queries_gap_idx" ON "public"."kb_queries" USING "btree" ("project_id", "known");



CREATE INDEX "kb_queries_gaptopic_idx" ON "public"."kb_queries" USING "btree" ("project_id") WHERE ("gap_topic" IS NOT NULL);



CREATE INDEX "kb_queries_project_idx" ON "public"."kb_queries" USING "btree" ("project_id", "created_at" DESC);



CREATE INDEX "kb_regions_project_idx" ON "public"."kb_regions" USING "btree" ("project_id", "status");



CREATE UNIQUE INDEX "kb_regions_uni" ON "public"."kb_regions" USING "btree" ("project_id", "lower"("name")) WHERE ("status" = 'active'::"text");



CREATE UNIQUE INDEX "kpi_project_entries_month_uniq" ON "public"."kpi_project_entries" USING "btree" ("project_id", "skill", "year", "month", "kpi_id") WHERE ("month" IS NOT NULL);



CREATE UNIQUE INDEX "kpi_project_entries_uniq" ON "public"."kpi_project_entries" USING "btree" ("project_id", "skill", "kw", "year", "kpi_id");



CREATE INDEX "mail_attachments_msg" ON "public"."mail_attachments" USING "btree" ("message_id");



CREATE INDEX "mail_messages_cv_idx" ON "public"."mail_messages" USING "btree" ("cv_id");



CREATE INDEX "mail_messages_emp_idx" ON "public"."mail_messages" USING "btree" ("employee_id");



CREATE INDEX "mail_messages_employee_filed_idx" ON "public"."mail_messages" USING "btree" ("employee_id", "filed_at") WHERE (("employee_id" IS NOT NULL) AND ("filed_at" IS NOT NULL));



CREATE INDEX "mail_messages_mid_idx" ON "public"."mail_messages" USING "btree" ("message_id");



CREATE INDEX "mail_messages_occ_idx" ON "public"."mail_messages" USING "btree" ("occurred_at");



CREATE INDEX "mgmt_call_items_bereich_idx" ON "public"."mgmt_call_items" USING "btree" ("bereich");



CREATE INDEX "mgmt_call_items_call_idx" ON "public"."mgmt_call_items" USING "btree" ("call_id");



CREATE INDEX "mgmt_call_items_carried_item_idx" ON "public"."mgmt_call_items" USING "btree" ("carried_from_item_id");



CREATE INDEX "mgmt_call_items_open_idx" ON "public"."mgmt_call_items" USING "btree" ("status") WHERE ("status" = 'open'::"text");



CREATE INDEX "mgmt_call_items_owner_emp_idx" ON "public"."mgmt_call_items" USING "btree" ("owner_employee_id");



CREATE INDEX "mgmt_calls_date_idx" ON "public"."mgmt_calls" USING "btree" ("call_date" DESC);



CREATE INDEX "mgmt_task_out_assignee_open_idx" ON "public"."mgmt_task_out" USING "btree" ("assignee_user") WHERE ("status" = 'open'::"text");



CREATE INDEX "mgmt_task_out_item_idx" ON "public"."mgmt_task_out" USING "btree" ("item_id");



CREATE UNIQUE INDEX "reminder_schedule_global" ON "public"."reminder_schedule" USING "btree" ("reminder_key") WHERE ("user_id" IS NULL);



CREATE UNIQUE INDEX "reminder_schedule_person" ON "public"."reminder_schedule" USING "btree" ("reminder_key", "user_id") WHERE ("user_id" IS NOT NULL);



CREATE INDEX "sales_events_lead_idx" ON "public"."sales_events" USING "btree" ("lead_id", "occurred_at");



CREATE INDEX "sales_leads_email_idx" ON "public"."sales_leads" USING "btree" ("lower"("contact_email"));



CREATE INDEX "sales_leads_score_idx" ON "public"."sales_leads" USING "btree" ("score" DESC NULLS LAST);



CREATE INDEX "sales_leads_stage_idx" ON "public"."sales_leads" USING "btree" ("stage");



CREATE INDEX "sales_leads_status_idx" ON "public"."sales_leads" USING "btree" ("status");



CREATE UNIQUE INDEX "sales_leads_unsub_idx" ON "public"."sales_leads" USING "btree" ("unsub_token");



CREATE UNIQUE INDEX "uq_agent_esc_open" ON "public"."agent_escalations" USING "btree" ("user_id", "subject") WHERE ("resolved_at" IS NULL);



CREATE UNIQUE INDEX "uq_call_score_config" ON "public"."call_score_config" USING "btree" (COALESCE("project_id", ''::"text"), COALESCE("skill", ''::"text"));



CREATE UNIQUE INDEX "uq_daily_hours" ON "public"."daily_hours" USING "btree" ("project_id", "employee_id", "work_date");



CREATE UNIQUE INDEX "uq_daily_mailer" ON "public"."daily_mailer" USING "btree" ("project_id", "employee_id", "work_date");



CREATE UNIQUE INDEX "uq_import_aliases" ON "public"."import_aliases" USING "btree" ("project_id", "lower"("alias_name"));



CREATE UNIQUE INDEX "uq_presentations_weekly" ON "public"."presentations" USING "btree" ("project_id", "skill", "period_year", "period_no") WHERE ("kind" = 'weekly'::"text");



CREATE UNIQUE INDEX "uq_weekly_calls" ON "public"."weekly_calls" USING "btree" ("project_id", "employee_id", "kw", "year");



CREATE UNIQUE INDEX "uq_weekly_gauges" ON "public"."weekly_gauges" USING "btree" ("project_id", "employee_id", "kw", "year");



CREATE UNIQUE INDEX "uq_weekly_hours" ON "public"."weekly_hours_legacy" USING "btree" ("project_id", "employee_id", "kw", "year");



CREATE UNIQUE INDEX "weekly_calls_pekjy" ON "public"."weekly_calls" USING "btree" ("project_id", "employee_id", "kw", "year");



CREATE OR REPLACE TRIGGER "app_users_last_admin" AFTER DELETE OR UPDATE ON "public"."app_users" FOR EACH STATEMENT EXECUTE FUNCTION "public"."enforce_last_admin"();



CREATE OR REPLACE TRIGGER "app_users_set_updated_at" BEFORE UPDATE ON "public"."app_users" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "clara_schedule_rejection_trg" AFTER UPDATE OF "status" ON "public"."cvs" FOR EACH ROW EXECUTE FUNCTION "public"."clara_schedule_rejection"();



CREATE OR REPLACE TRIGGER "cvs_set_updated_at" BEFORE UPDATE ON "public"."cvs" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "dm_messages_touch" AFTER INSERT ON "public"."dm_messages" FOR EACH ROW EXECUTE FUNCTION "public"."dm_touch_thread"();



CREATE OR REPLACE TRIGGER "mgmt_task_out_guard_t" BEFORE UPDATE ON "public"."mgmt_task_out" FOR EACH ROW EXECUTE FUNCTION "public"."mgmt_task_out_guard"();



CREATE OR REPLACE TRIGGER "mgmt_task_out_sync_t" AFTER UPDATE ON "public"."mgmt_task_out" FOR EACH ROW EXECUTE FUNCTION "public"."mgmt_task_out_sync"();



CREATE OR REPLACE TRIGGER "perm_area_grant_management_t" AFTER INSERT ON "public"."permission_areas" FOR EACH ROW EXECUTE FUNCTION "public"."perm_area_grant_management"();



CREATE OR REPLACE TRIGGER "trg_cvs_guard_employee_dup" BEFORE INSERT ON "public"."cvs" FOR EACH ROW EXECUTE FUNCTION "public"."cvs_guard_employee_dup"();



CREATE OR REPLACE TRIGGER "trg_cvs_public_code" BEFORE INSERT ON "public"."cvs" FOR EACH ROW EXECUTE FUNCTION "public"."cvs_assign_public_code"();



CREATE OR REPLACE TRIGGER "trg_lead_state_persist" AFTER UPDATE ON "public"."windsor_leads" FOR EACH ROW EXECUTE FUNCTION "public"."lead_state_persist"();



CREATE OR REPLACE TRIGGER "trg_lead_state_restore" BEFORE INSERT ON "public"."windsor_leads" FOR EACH ROW EXECUTE FUNCTION "public"."lead_state_restore"();



CREATE OR REPLACE TRIGGER "trg_protect_salary_on_update" BEFORE UPDATE ON "public"."employees" FOR EACH ROW EXECUTE FUNCTION "public"."protect_salary_on_update"();



CREATE OR REPLACE TRIGGER "trg_sales_leads_tier" BEFORE INSERT OR UPDATE OF "contact_email" ON "public"."sales_leads" FOR EACH ROW EXECUTE FUNCTION "public"."sales_leads_set_tier"();



CREATE OR REPLACE TRIGGER "trg_windsor_auto_discard" BEFORE INSERT OR UPDATE OF "status_review" ON "public"."windsor_leads" FOR EACH ROW EXECUTE FUNCTION "public"."windsor_leads_auto_discard"();



CREATE OR REPLACE TRIGGER "trg_windsor_marketing_dedup" AFTER INSERT ON "public"."windsor_marketing" FOR EACH STATEMENT EXECUTE FUNCTION "public"."windsor_marketing_dedup"();



CREATE OR REPLACE TRIGGER "update_employees_updated_at" BEFORE UPDATE ON "public"."employees" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_payslips_updated_at" BEFORE UPDATE ON "public"."payslips" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



ALTER TABLE ONLY "public"."agent_action_log"
    ADD CONSTRAINT "agent_action_log_insight_id_fkey" FOREIGN KEY ("insight_id") REFERENCES "public"."agent_insights"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."agent_insights"
    ADD CONSTRAINT "agent_insights_observation_id_fkey" FOREIGN KEY ("observation_id") REFERENCES "public"."agent_observations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."app_users"
    ADD CONSTRAINT "app_users_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."employees"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."app_users"
    ADD CONSTRAINT "app_users_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."applicant_messages"
    ADD CONSTRAINT "applicant_messages_cv_id_fkey" FOREIGN KEY ("cv_id") REFERENCES "public"."cvs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."calendar_events"
    ADD CONSTRAINT "calendar_events_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."calendar_overrides"
    ADD CONSTRAINT "calendar_overrides_done_by_fkey" FOREIGN KEY ("done_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."calendar_overrides"
    ADD CONSTRAINT "calendar_overrides_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."calendar_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."call_samples"
    ADD CONSTRAINT "call_samples_conducted_by_fkey" FOREIGN KEY ("conducted_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."call_samples"
    ADD CONSTRAINT "call_samples_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."call_scores"
    ADD CONSTRAINT "call_scores_criterion_id_fkey" FOREIGN KEY ("criterion_id") REFERENCES "public"."call_criteria"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."call_scores"
    ADD CONSTRAINT "call_scores_sample_id_fkey" FOREIGN KEY ("sample_id") REFERENCES "public"."call_samples"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_flags"
    ADD CONSTRAINT "chat_flags_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."dm_messages"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."clara_handovers"
    ADD CONSTRAINT "clara_handovers_cv_id_fkey" FOREIGN KEY ("cv_id") REFERENCES "public"."cvs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."clara_rejections"
    ADD CONSTRAINT "clara_rejections_cv_id_fkey" FOREIGN KEY ("cv_id") REFERENCES "public"."cvs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contract_templates"
    ADD CONSTRAINT "contract_templates_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."cv_enrich_invites"
    ADD CONSTRAINT "cv_enrich_invites_cv_id_fkey" FOREIGN KEY ("cv_id") REFERENCES "public"."cvs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cv_enrich_invites"
    ADD CONSTRAINT "cv_enrich_invites_form_id_fkey" FOREIGN KEY ("form_id") REFERENCES "public"."cv_enrich_forms"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."daily_hours"
    ADD CONSTRAINT "daily_hours_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_hours"
    ADD CONSTRAINT "daily_hours_import_id_fkey" FOREIGN KEY ("import_id") REFERENCES "public"."data_imports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."daily_mailer"
    ADD CONSTRAINT "daily_mailer_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_mailer"
    ADD CONSTRAINT "daily_mailer_import_id_fkey" FOREIGN KEY ("import_id") REFERENCES "public"."data_imports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."daily_report_summaries"
    ADD CONSTRAINT "daily_report_summaries_generated_by_fkey" FOREIGN KEY ("generated_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."daily_reports"
    ADD CONSTRAINT "daily_reports_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_tasks_done"
    ADD CONSTRAINT "daily_tasks_done_done_by_fkey" FOREIGN KEY ("done_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."data_imports"
    ADD CONSTRAINT "data_imports_uploaded_by_fkey" FOREIGN KEY ("uploaded_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."dm_messages"
    ADD CONSTRAINT "dm_messages_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "public"."dm_threads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dm_participants"
    ADD CONSTRAINT "dm_participants_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "public"."dm_threads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dm_reads"
    ADD CONSTRAINT "dm_reads_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."dm_messages"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."employee_contracts"
    ADD CONSTRAINT "employee_contracts_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."employee_contracts"
    ADD CONSTRAINT "employee_contracts_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."employee_contracts"
    ADD CONSTRAINT "employee_contracts_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "public"."contract_templates"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."employee_documents"
    ADD CONSTRAINT "employee_documents_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."employee_documents"
    ADD CONSTRAINT "employee_documents_uploaded_by_fkey" FOREIGN KEY ("uploaded_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."feedback_answers"
    ADD CONSTRAINT "feedback_answers_question_id_fkey" FOREIGN KEY ("question_id") REFERENCES "public"."feedback_questions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."feedback_answers"
    ADD CONSTRAINT "feedback_answers_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."feedback_sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."feedback_sessions"
    ADD CONSTRAINT "feedback_sessions_conducted_by_fkey" FOREIGN KEY ("conducted_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."feedback_sessions"
    ADD CONSTRAINT "feedback_sessions_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."forecast_actuals"
    ADD CONSTRAINT "forecast_actuals_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."forecast_demand"
    ADD CONSTRAINT "forecast_demand_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."import_aliases"
    ADD CONSTRAINT "import_aliases_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."import_aliases"
    ADD CONSTRAINT "import_aliases_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."interview_invites"
    ADD CONSTRAINT "interview_invites_cv_id_fkey" FOREIGN KEY ("cv_id") REFERENCES "public"."cvs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."kb_chunks"
    ADD CONSTRAINT "kb_chunks_document_id_fkey" FOREIGN KEY ("document_id") REFERENCES "public"."kb_documents"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."kb_chunks"
    ADD CONSTRAINT "kb_chunks_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."kb_documents"
    ADD CONSTRAINT "kb_documents_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."kb_documents"
    ADD CONSTRAINT "kb_documents_supersedes_fkey" FOREIGN KEY ("supersedes") REFERENCES "public"."kb_documents"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."kb_facts"
    ADD CONSTRAINT "kb_facts_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."kb_facts"
    ADD CONSTRAINT "kb_facts_source_document_id_fkey" FOREIGN KEY ("source_document_id") REFERENCES "public"."kb_documents"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."kb_queries"
    ADD CONSTRAINT "kb_queries_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."kb_regions"
    ADD CONSTRAINT "kb_regions_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."kpi_entries"
    ADD CONSTRAINT "kpi_entries_emp_id_fkey" FOREIGN KEY ("emp_id") REFERENCES "public"."employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."kpi_entries"
    ADD CONSTRAINT "kpi_entries_import_id_fkey" FOREIGN KEY ("import_id") REFERENCES "public"."data_imports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."kpi_project_entries"
    ADD CONSTRAINT "kpi_project_entries_import_id_fkey" FOREIGN KEY ("import_id") REFERENCES "public"."data_imports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."location_monthly"
    ADD CONSTRAINT "location_monthly_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."mail_attachments"
    ADD CONSTRAINT "mail_attachments_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."mail_messages"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."mail_messages"
    ADD CONSTRAINT "mail_messages_cv_id_fkey" FOREIGN KEY ("cv_id") REFERENCES "public"."cvs"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."mail_messages"
    ADD CONSTRAINT "mail_messages_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."employees"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."meeting_note_comments"
    ADD CONSTRAINT "meeting_note_comments_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."meeting_note_comments"
    ADD CONSTRAINT "meeting_note_comments_item_id_fkey" FOREIGN KEY ("item_id") REFERENCES "public"."meeting_note_items"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."meeting_note_comments"
    ADD CONSTRAINT "meeting_note_comments_note_id_fkey" FOREIGN KEY ("note_id") REFERENCES "public"."meeting_notes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."meeting_note_items"
    ADD CONSTRAINT "meeting_note_items_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."meeting_note_items"
    ADD CONSTRAINT "meeting_note_items_note_id_fkey" FOREIGN KEY ("note_id") REFERENCES "public"."meeting_notes"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."meeting_notes"
    ADD CONSTRAINT "meeting_notes_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."mgmt_call_items"
    ADD CONSTRAINT "mgmt_call_items_call_id_fkey" FOREIGN KEY ("call_id") REFERENCES "public"."mgmt_calls"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."mgmt_call_items"
    ADD CONSTRAINT "mgmt_call_items_carried_from_item_id_fkey" FOREIGN KEY ("carried_from_item_id") REFERENCES "public"."mgmt_call_items"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."mgmt_call_items"
    ADD CONSTRAINT "mgmt_call_items_owner_employee_id_fkey" FOREIGN KEY ("owner_employee_id") REFERENCES "public"."employees"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."mgmt_task_out"
    ADD CONSTRAINT "mgmt_task_out_item_id_fkey" FOREIGN KEY ("item_id") REFERENCES "public"."mgmt_call_items"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."notify_prefs"
    ADD CONSTRAINT "notify_prefs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."org_nodes"
    ADD CONSTRAINT "org_nodes_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "public"."org_nodes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."org_nodes"
    ADD CONSTRAINT "org_nodes_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."partner_agents"
    ADD CONSTRAINT "partner_agents_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."payroll_inputs"
    ADD CONSTRAINT "payroll_inputs_emp_id_fkey" FOREIGN KEY ("emp_id") REFERENCES "public"."employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."payslips"
    ADD CONSTRAINT "payslips_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."employees"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."presentation_comments"
    ADD CONSTRAINT "presentation_comments_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."presentation_comments"
    ADD CONSTRAINT "presentation_comments_presentation_id_fkey" FOREIGN KEY ("presentation_id") REFERENCES "public"."presentations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."presentations"
    ADD CONSTRAINT "presentations_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "public"."presentation_templates"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."project_skill_profiles"
    ADD CONSTRAINT "project_skill_profiles_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_skills"
    ADD CONSTRAINT "project_skills_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_trainings"
    ADD CONSTRAINT "project_trainings_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."report_forecast"
    ADD CONSTRAINT "report_forecast_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."report_fte"
    ADD CONSTRAINT "report_fte_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."report_fte"
    ADD CONSTRAINT "report_fte_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."report_longterm"
    ADD CONSTRAINT "report_longterm_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."report_measures"
    ADD CONSTRAINT "report_measures_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."rk_monthly"
    ADD CONSTRAINT "rk_monthly_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."rk_overhead"
    ADD CONSTRAINT "rk_overhead_emp_id_fkey" FOREIGN KEY ("emp_id") REFERENCES "public"."employees"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."rk_overhead"
    ADD CONSTRAINT "rk_overhead_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."role_permissions"
    ADD CONSTRAINT "role_permissions_area_key_fkey" FOREIGN KEY ("area_key") REFERENCES "public"."permission_areas"("key");



ALTER TABLE ONLY "public"."sales_events"
    ADD CONSTRAINT "sales_events_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "public"."sales_leads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shift_assignments"
    ADD CONSTRAINT "shift_assignments_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shift_assignments"
    ADD CONSTRAINT "shift_assignments_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."shift_checkins"
    ADD CONSTRAINT "shift_checkins_confirmed_by_fkey" FOREIGN KEY ("confirmed_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."shift_checkins"
    ADD CONSTRAINT "shift_checkins_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."spaces"
    ADD CONSTRAINT "spaces_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."task_assignments"
    ADD CONSTRAINT "task_assignments_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."task_snooze"
    ADD CONSTRAINT "task_snooze_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."task_takeover"
    ADD CONSTRAINT "task_takeover_taken_over_by_fkey" FOREIGN KEY ("taken_over_by") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."time_pins"
    ADD CONSTRAINT "time_pins_emp_id_fkey" FOREIGN KEY ("emp_id") REFERENCES "public"."employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."time_sessions"
    ADD CONSTRAINT "time_sessions_emp_id_fkey" FOREIGN KEY ("emp_id") REFERENCES "public"."employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."training_plans"
    ADD CONSTRAINT "training_plans_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_permissions"
    ADD CONSTRAINT "user_permissions_area_key_fkey" FOREIGN KEY ("area_key") REFERENCES "public"."permission_areas"("key");



ALTER TABLE ONLY "public"."vacation_accounts"
    ADD CONSTRAINT "vacation_accounts_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."weekly_calls"
    ADD CONSTRAINT "weekly_calls_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."weekly_calls"
    ADD CONSTRAINT "weekly_calls_import_id_fkey" FOREIGN KEY ("import_id") REFERENCES "public"."data_imports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."weekly_gauges"
    ADD CONSTRAINT "weekly_gauges_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."weekly_gauges"
    ADD CONSTRAINT "weekly_gauges_import_id_fkey" FOREIGN KEY ("import_id") REFERENCES "public"."data_imports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."weekly_hours_legacy"
    ADD CONSTRAINT "weekly_hours_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."weekly_hours_legacy"
    ADD CONSTRAINT "weekly_hours_import_id_fkey" FOREIGN KEY ("import_id") REFERENCES "public"."data_imports"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."wheel_spins"
    ADD CONSTRAINT "wheel_spins_emp_id_fkey" FOREIGN KEY ("emp_id") REFERENCES "public"."employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."wheel_spins"
    ADD CONSTRAINT "wheel_spins_special_id_fkey" FOREIGN KEY ("special_id") REFERENCES "public"."wheel_specials"("id") ON DELETE SET NULL;



CREATE POLICY "Client reads own project org" ON "public"."org_nodes" FOR SELECT TO "authenticated" USING ((("project_id" = "public"."get_my_client_project_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['kunde'::"text"]))))));



CREATE POLICY "Client sees own account" ON "public"."client_accounts" FOR SELECT TO "authenticated" USING (("id" = ( SELECT "app_users"."client_id"
   FROM "public"."app_users"
  WHERE ("app_users"."user_id" = "auth"."uid"()))));



CREATE POLICY "HR full access client_accounts" ON "public"."client_accounts" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



CREATE POLICY "HR full access org_nodes" ON "public"."org_nodes" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"]))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



CREATE POLICY "HR full access showcases" ON "public"."showcases" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text", 'projektleiter'::"text", 'teamlead'::"text"]))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text", 'projektleiter'::"text", 'teamlead'::"text"])))));



CREATE POLICY "aal_select" ON "public"."agent_action_log" FOR SELECT TO "authenticated" USING ((("actor" = "auth"."uid"()) OR "public"."is_management"()));



CREATE POLICY "activity_insert" ON "public"."activity_log" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."activity_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "activity_read" ON "public"."activity_log" FOR SELECT TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'protokoll'::"text") <> 'none'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'protokoll'::"text", ( SELECT "e"."project_id"
   FROM ("public"."app_users" "au"
     JOIN "public"."employees" "e" ON (("e"."id" = "au"."employee_id")))
  WHERE ("au"."user_id" = "activity_log"."user_id")
 LIMIT 1), NULL::"text")));



ALTER TABLE "public"."agent_action_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."agent_actions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "agent_actions_sel" ON "public"."agent_actions" FOR SELECT TO "authenticated" USING ("public"."is_management"());



ALTER TABLE "public"."agent_checks" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "agent_checks_sel" ON "public"."agent_checks" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "agent_conv_del" ON "public"."agent_conversations" FOR DELETE USING (("user_id" = "auth"."uid"()));



CREATE POLICY "agent_conv_sel" ON "public"."agent_conversations" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."agent_conversations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."agent_digests" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "agent_digests_sel" ON "public"."agent_digests" FOR SELECT TO "authenticated" USING ("public"."is_management"());



CREATE POLICY "agent_esc_sel" ON "public"."agent_escalations" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



ALTER TABLE "public"."agent_escalations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."agent_handoffs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "agent_handoffs_read" ON "public"."agent_handoffs" FOR SELECT USING ("public"."is_management"());



ALTER TABLE "public"."agent_insights" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "agent_insights_sel" ON "public"."agent_insights" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "agent_obs_sel" ON "public"."agent_observations" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



ALTER TABLE "public"."agent_observations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."agent_prefs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "agent_prefs_own" ON "public"."agent_prefs" TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."ai_access_prefs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ai_access_prefs_mgmt" ON "public"."ai_access_prefs" TO "authenticated" USING ("public"."is_management"()) WITH CHECK ("public"."is_management"());



ALTER TABLE "public"."ai_agents" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ai_agents_sel" ON "public"."ai_agents" FOR SELECT TO "authenticated" USING ((("visibility" = 'all'::"text") OR (("visibility" = 'management'::"text") AND "public"."is_management"()) OR (("visibility" = 'admin'::"text") AND "public"."is_admin"())));



CREATE POLICY "ai_agents_write" ON "public"."ai_agents" TO "authenticated" USING ("public"."is_management"()) WITH CHECK ("public"."is_management"());



ALTER TABLE "public"."app_config" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "app_config HR write" ON "public"."app_config" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"]))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



CREATE POLICY "app_config read internal" ON "public"."app_config" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text", 'teamlead'::"text", 'projektleiter'::"text", 'mitarbeiter'::"text"])))));



ALTER TABLE "public"."app_users" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "app_users_insert_admin" ON "public"."app_users" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_admin"());



CREATE POLICY "app_users_select_admin" ON "public"."app_users" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "app_users_select_self" ON "public"."app_users" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "app_users_update_admin" ON "public"."app_users" FOR UPDATE TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



ALTER TABLE "public"."applicant_messages" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "applicant_messages_sel" ON "public"."applicant_messages" FOR SELECT TO "authenticated" USING (("public"."is_admin"() OR "public"."is_planner"()));



ALTER TABLE "public"."assistant_gaps" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "assistant_gaps_del" ON "public"."assistant_gaps" FOR DELETE TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "assistant_gaps_sel" ON "public"."assistant_gaps" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "assistant_gaps_upd" ON "public"."assistant_gaps" FOR UPDATE TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "cal_ev_delete" ON "public"."calendar_events" FOR DELETE TO "authenticated" USING (("public"."is_admin"() OR ("created_by" = "auth"."uid"())));



CREATE POLICY "cal_ev_insert" ON "public"."calendar_events" FOR INSERT TO "authenticated" WITH CHECK (("created_by" = "auth"."uid"()));



CREATE POLICY "cal_ev_select" ON "public"."calendar_events" FOR SELECT TO "authenticated" USING (("public"."is_admin"() OR ("created_by" = "auth"."uid"()) OR ("public"."get_my_employee_id"() = ANY ("participants")) OR (("visible_roles" <> '{}'::"text"[]) AND ("visible_roles" && "public"."get_my_role_keys"()))));



CREATE POLICY "cal_ev_update" ON "public"."calendar_events" FOR UPDATE TO "authenticated" USING (("public"."is_admin"() OR ("created_by" = "auth"."uid"()))) WITH CHECK (("public"."is_admin"() OR ("created_by" = "auth"."uid"())));



CREATE POLICY "cal_ovr_delete" ON "public"."calendar_overrides" FOR DELETE TO "authenticated" USING ("public"."calendar_event_visible"("event_id"));



CREATE POLICY "cal_ovr_insert" ON "public"."calendar_overrides" FOR INSERT TO "authenticated" WITH CHECK ("public"."calendar_event_visible"("event_id"));



CREATE POLICY "cal_ovr_select" ON "public"."calendar_overrides" FOR SELECT TO "authenticated" USING ("public"."calendar_event_visible"("event_id"));



CREATE POLICY "cal_ovr_update" ON "public"."calendar_overrides" FOR UPDATE TO "authenticated" USING ("public"."calendar_event_visible"("event_id")) WITH CHECK ("public"."calendar_event_visible"("event_id"));



ALTER TABLE "public"."calendar_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."calendar_overrides" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."call_criteria" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "call_criteria_admin" ON "public"."call_criteria" TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "call_criteria_callqa" ON "public"."call_criteria" USING (("public"."perm_mode"("auth"."uid"(), 'callqa'::"text") = 'edit'::"text")) WITH CHECK (("public"."perm_mode"("auth"."uid"(), 'callqa'::"text") = 'edit'::"text"));



ALTER TABLE "public"."call_samples" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "call_samples_admin" ON "public"."call_samples" TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "call_samples_callqa" ON "public"."call_samples" USING (("public"."perm_mode"("auth"."uid"(), 'callqa'::"text") = 'edit'::"text")) WITH CHECK (("public"."perm_mode"("auth"."uid"(), 'callqa'::"text") = 'edit'::"text"));



CREATE POLICY "call_samples_own" ON "public"."call_samples" FOR SELECT TO "authenticated" USING (("employee_id" = "public"."get_my_employee_id"()));



ALTER TABLE "public"."call_score_config" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "call_score_config_admin" ON "public"."call_score_config" TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "call_score_config_read" ON "public"."call_score_config" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."call_scores" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "call_scores_admin" ON "public"."call_scores" TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "call_scores_callqa" ON "public"."call_scores" USING (("public"."perm_mode"("auth"."uid"(), 'callqa'::"text") = 'edit'::"text")) WITH CHECK (("public"."perm_mode"("auth"."uid"(), 'callqa'::"text") = 'edit'::"text"));



CREATE POLICY "call_scores_own" ON "public"."call_scores" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."call_samples" "s"
  WHERE (("s"."id" = "call_scores"."sample_id") AND ("s"."employee_id" = "public"."get_my_employee_id"())))));



ALTER TABLE "public"."chat_flags" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "chat_flags_sel" ON "public"."chat_flags" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "chat_flags_upd" ON "public"."chat_flags" FOR UPDATE TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



ALTER TABLE "public"."clara_handovers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "clara_handovers_sel" ON "public"."clara_handovers" FOR SELECT USING (("public"."is_management"() OR "public"."is_hr"()));



CREATE POLICY "clara_handovers_upd" ON "public"."clara_handovers" FOR UPDATE USING (("public"."is_management"() OR "public"."is_hr"())) WITH CHECK (("public"."is_management"() OR "public"."is_hr"()));



CREATE POLICY "clara_rej_sel" ON "public"."clara_rejections" FOR SELECT USING (("public"."is_management"() OR "public"."is_hr"()));



CREATE POLICY "clara_rej_upd" ON "public"."clara_rejections" FOR UPDATE USING (("public"."is_management"() OR "public"."is_hr"())) WITH CHECK (("public"."is_management"() OR "public"."is_hr"()));



ALTER TABLE "public"."clara_rejections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."client_accounts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."client_errors" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "client_errors_mgmt_delete" ON "public"."client_errors" FOR DELETE TO "authenticated" USING ("public"."is_management"());



CREATE POLICY "client_errors_mgmt_select" ON "public"."client_errors" FOR SELECT TO "authenticated" USING ("public"."is_management"());



CREATE POLICY "client_errors_mgmt_update" ON "public"."client_errors" FOR UPDATE TO "authenticated" USING ("public"."is_management"()) WITH CHECK ("public"."is_management"());



ALTER TABLE "public"."client_meeting_briefs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "cmb_rw" ON "public"."client_meeting_briefs" USING (("public"."is_management"() OR ("public"."is_planner"() AND ("project_id" = "public"."get_my_employee_project_id"())))) WITH CHECK (("public"."is_management"() OR ("public"."is_planner"() AND ("project_id" = "public"."get_my_employee_project_id"()))));



ALTER TABLE "public"."contract_templates" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "contract_templates_admin" ON "public"."contract_templates" TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



ALTER TABLE "public"."cv_enrich_forms" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "cv_enrich_forms_sel" ON "public"."cv_enrich_forms" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "cv_enrich_forms_write" ON "public"."cv_enrich_forms" TO "authenticated" USING ("public"."is_management"()) WITH CHECK ("public"."is_management"());



CREATE POLICY "cv_enrich_ins" ON "public"."cv_enrich_invites" FOR INSERT TO "authenticated" WITH CHECK (true);



ALTER TABLE "public"."cv_enrich_invites" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "cv_enrich_sel" ON "public"."cv_enrich_invites" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."cvs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "cvs_perm_delete" ON "public"."cvs" FOR DELETE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'bewerber'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'bewerber'::"text", "project_id", NULL::"text")));



CREATE POLICY "cvs_perm_insert" ON "public"."cvs" FOR INSERT TO "authenticated" WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'bewerber'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'bewerber'::"text", "project_id", NULL::"text")));



CREATE POLICY "cvs_perm_select" ON "public"."cvs" FOR SELECT TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'bewerber'::"text") <> 'none'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'bewerber'::"text", "project_id", NULL::"text")));



CREATE POLICY "cvs_perm_update" ON "public"."cvs" FOR UPDATE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'bewerber'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'bewerber'::"text", "project_id", NULL::"text"))) WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'bewerber'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'bewerber'::"text", "project_id", NULL::"text")));



ALTER TABLE "public"."daily_hours" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."daily_mailer" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."daily_report_summaries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."daily_reports" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."daily_tasks_done" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."data_imports" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "data_imports_mgmt" ON "public"."data_imports" TO "authenticated" USING (("public"."is_management"() OR ("public"."is_planner"() AND ("project_id" = "public"."get_my_employee_project_id"())))) WITH CHECK (("public"."is_management"() OR ("public"."is_planner"() AND ("project_id" = "public"."get_my_employee_project_id"()))));



CREATE POLICY "dh_perm_delete" ON "public"."daily_hours" FOR DELETE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") = 'edit'::"text") AND (NOT "public"."is_hr"()) AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text")));



CREATE POLICY "dh_perm_insert" ON "public"."daily_hours" FOR INSERT TO "authenticated" WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") = 'edit'::"text") AND (NOT "public"."is_hr"()) AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text")));



CREATE POLICY "dh_perm_select" ON "public"."daily_hours" FOR SELECT TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") <> 'none'::"text") AND (NOT "public"."is_hr"()) AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text")));



CREATE POLICY "dh_perm_update" ON "public"."daily_hours" FOR UPDATE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") = 'edit'::"text") AND (NOT "public"."is_hr"()) AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text"))) WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") = 'edit'::"text") AND (NOT "public"."is_hr"()) AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text")));



ALTER TABLE "public"."dm_messages" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "dm_msg_ins" ON "public"."dm_messages" FOR INSERT TO "authenticated" WITH CHECK ((("from_emp_id" = "public"."get_my_employee_id"()) AND "public"."dm_is_member"("thread_id")));



CREATE POLICY "dm_msg_sel" ON "public"."dm_messages" FOR SELECT TO "authenticated" USING ("public"."dm_is_member"("thread_id"));



CREATE POLICY "dm_part_sel" ON "public"."dm_participants" FOR SELECT TO "authenticated" USING ("public"."dm_is_member"("thread_id"));



CREATE POLICY "dm_part_upd_self" ON "public"."dm_participants" FOR UPDATE TO "authenticated" USING (("emp_id" = "public"."get_my_employee_id"())) WITH CHECK (("emp_id" = "public"."get_my_employee_id"()));



ALTER TABLE "public"."dm_participants" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "dm_perm_select" ON "public"."daily_mailer" FOR SELECT TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'kpi'::"text") <> 'none'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'kpi'::"text", "project_id", NULL::"text")));



CREATE POLICY "dm_perm_write" ON "public"."daily_mailer" TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'kpi'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'kpi'::"text", "project_id", NULL::"text"))) WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'kpi'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'kpi'::"text", "project_id", NULL::"text")));



ALTER TABLE "public"."dm_reads" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "dm_reads_ins" ON "public"."dm_reads" FOR INSERT TO "authenticated" WITH CHECK ((("emp_id" = "public"."get_my_employee_id"()) AND "public"."dm_is_member"(( SELECT "dm_messages"."thread_id"
   FROM "public"."dm_messages"
  WHERE ("dm_messages"."id" = "dm_reads"."message_id")))));



CREATE POLICY "dm_reads_sel" ON "public"."dm_reads" FOR SELECT TO "authenticated" USING ("public"."dm_is_member"(( SELECT "dm_messages"."thread_id"
   FROM "public"."dm_messages"
  WHERE ("dm_messages"."id" = "dm_reads"."message_id"))));



ALTER TABLE "public"."dm_threads" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "dm_threads_sel" ON "public"."dm_threads" FOR SELECT TO "authenticated" USING ("public"."dm_is_member"("id"));



CREATE POLICY "dr_delete" ON "public"."daily_reports" FOR DELETE TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "dr_insert" ON "public"."daily_reports" FOR INSERT TO "authenticated" WITH CHECK ((("employee_id" = "public"."get_my_employee_id"()) AND ("report_date" <= (("now"() AT TIME ZONE 'Europe/Berlin'::"text"))::"date") AND ("report_date" >= ((("now"() AT TIME ZONE 'Europe/Berlin'::"text"))::"date" - 1))));



CREATE POLICY "dr_select" ON "public"."daily_reports" FOR SELECT TO "authenticated" USING (("public"."is_admin"() OR ("employee_id" = "public"."get_my_employee_id"()) OR ("public"."is_planner"() AND ("project_id" = "public"."get_my_employee_project_id"()))));



CREATE POLICY "dr_update" ON "public"."daily_reports" FOR UPDATE TO "authenticated" USING ((("employee_id" = "public"."get_my_employee_id"()) AND ("report_date" >= ((("now"() AT TIME ZONE 'Europe/Berlin'::"text"))::"date" - 1)))) WITH CHECK ((("employee_id" = "public"."get_my_employee_id"()) AND ("report_date" <= (("now"() AT TIME ZONE 'Europe/Berlin'::"text"))::"date") AND ("report_date" >= ((("now"() AT TIME ZONE 'Europe/Berlin'::"text"))::"date" - 1))));



CREATE POLICY "drs_select" ON "public"."daily_report_summaries" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "drs_write" ON "public"."daily_report_summaries" TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "dtd_internal" ON "public"."daily_tasks_done" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users" "u"
  WHERE (("u"."user_id" = "auth"."uid"()) AND "u"."active" AND (NOT ('kunde'::"text" = ANY (COALESCE("u"."role_keys", '{}'::"text"[])))))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users" "u"
  WHERE (("u"."user_id" = "auth"."uid"()) AND "u"."active" AND (NOT ('kunde'::"text" = ANY (COALESCE("u"."role_keys", '{}'::"text"[]))))))));



CREATE POLICY "emp_perm_delete" ON "public"."employees" FOR DELETE TO "authenticated" USING (("public"."perm_salary_ok"("auth"."uid"(), 'emp'::"text", "id") AND ("public"."perm_mode"("auth"."uid"(), 'emp'::"text") = 'edit'::"text")));



CREATE POLICY "emp_perm_insert" ON "public"."employees" FOR INSERT TO "authenticated" WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'emp'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'emp'::"text", "project_id", NULL::"text")));



CREATE POLICY "emp_perm_select" ON "public"."employees" FOR SELECT TO "authenticated" USING (("public"."perm_salary_ok"("auth"."uid"(), 'emp'::"text", "id") OR ("id" = "public"."perm_caller_emp_id"())));



CREATE POLICY "emp_perm_update" ON "public"."employees" FOR UPDATE TO "authenticated" USING (((("public"."perm_mode"("auth"."uid"(), 'emp'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'emp'::"text", "project_id", NULL::"text")) OR ("id" = "public"."perm_caller_emp_id"()))) WITH CHECK (((("public"."perm_mode"("auth"."uid"(), 'emp'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'emp'::"text", "project_id", NULL::"text")) OR ("id" = "public"."perm_caller_emp_id"())));



ALTER TABLE "public"."employee_contracts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "employee_contracts_admin" ON "public"."employee_contracts" TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



ALTER TABLE "public"."employee_documents" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "employee_documents_admin_all" ON "public"."employee_documents" TO "authenticated" USING (("public"."is_management"() OR ("public"."is_hr"() AND (NOT "public"."is_protected_employee"("employee_id"))))) WITH CHECK (("public"."is_management"() OR ("public"."is_hr"() AND (NOT "public"."is_protected_employee"("employee_id")))));



CREATE POLICY "employee_documents_select_own" ON "public"."employee_documents" FOR SELECT TO "authenticated" USING (("employee_id" = "public"."my_employee_id"()));



ALTER TABLE "public"."employees" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "fa_perm_delete" ON "public"."forecast_actuals" FOR DELETE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'wirtschaft'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'wirtschaft'::"text", "project_id", NULL::"text")));



CREATE POLICY "fa_perm_insert" ON "public"."forecast_actuals" FOR INSERT TO "authenticated" WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'wirtschaft'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'wirtschaft'::"text", "project_id", NULL::"text")));



CREATE POLICY "fa_perm_select" ON "public"."forecast_actuals" FOR SELECT TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'wirtschaft'::"text") <> 'none'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'wirtschaft'::"text", "project_id", NULL::"text")));



CREATE POLICY "fa_perm_update" ON "public"."forecast_actuals" FOR UPDATE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'wirtschaft'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'wirtschaft'::"text", "project_id", NULL::"text"))) WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'wirtschaft'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'wirtschaft'::"text", "project_id", NULL::"text")));



CREATE POLICY "fd_perm_delete" ON "public"."forecast_demand" FOR DELETE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text")));



CREATE POLICY "fd_perm_insert" ON "public"."forecast_demand" FOR INSERT TO "authenticated" WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text")));



CREATE POLICY "fd_perm_select" ON "public"."forecast_demand" FOR SELECT TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") <> 'none'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text")));



CREATE POLICY "fd_perm_update" ON "public"."forecast_demand" FOR UPDATE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text"))) WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text")));



ALTER TABLE "public"."feedback_answers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "feedback_answers_admin" ON "public"."feedback_answers" TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "feedback_answers_lead" ON "public"."feedback_answers" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."feedback_sessions" "s"
  WHERE (("s"."id" = "feedback_answers"."session_id") AND "public"."is_planner"() AND (COALESCE("s"."project_id", ( SELECT "e"."project_id"
           FROM "public"."employees" "e"
          WHERE ("e"."id" = "s"."employee_id"))) = "public"."get_my_employee_project_id"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."feedback_sessions" "s"
  WHERE (("s"."id" = "feedback_answers"."session_id") AND "public"."is_planner"() AND (COALESCE("s"."project_id", ( SELECT "e"."project_id"
           FROM "public"."employees" "e"
          WHERE ("e"."id" = "s"."employee_id"))) = "public"."get_my_employee_project_id"())))));



CREATE POLICY "feedback_answers_own" ON "public"."feedback_answers" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."feedback_sessions" "s"
  WHERE (("s"."id" = "feedback_answers"."session_id") AND ("s"."employee_id" = "public"."get_my_employee_id"())))));



ALTER TABLE "public"."feedback_questions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "feedback_questions_admin" ON "public"."feedback_questions" TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "feedback_questions_lead_read" ON "public"."feedback_questions" FOR SELECT TO "authenticated" USING ("public"."is_planner"());



ALTER TABLE "public"."feedback_sessions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "feedback_sessions_admin" ON "public"."feedback_sessions" TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "feedback_sessions_lead" ON "public"."feedback_sessions" TO "authenticated" USING (("public"."is_planner"() AND (COALESCE("project_id", ( SELECT "e"."project_id"
   FROM "public"."employees" "e"
  WHERE ("e"."id" = "feedback_sessions"."employee_id"))) = "public"."get_my_employee_project_id"()))) WITH CHECK (("public"."is_planner"() AND (COALESCE("project_id", ( SELECT "e"."project_id"
   FROM "public"."employees" "e"
  WHERE ("e"."id" = "feedback_sessions"."employee_id"))) = "public"."get_my_employee_project_id"())));



CREATE POLICY "feedback_sessions_own" ON "public"."feedback_sessions" FOR SELECT TO "authenticated" USING (("employee_id" = "public"."get_my_employee_id"()));



ALTER TABLE "public"."forecast_actuals" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."forecast_config" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "forecast_config HR write" ON "public"."forecast_config" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"]))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



CREATE POLICY "forecast_config read internal" ON "public"."forecast_config" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text", 'teamlead'::"text", 'projektleiter'::"text", 'mitarbeiter'::"text"])))));



ALTER TABLE "public"."forecast_demand" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."import_aliases" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "import_aliases_rw" ON "public"."import_aliases" USING (("public"."is_management"() OR ("public"."is_planner"() AND ("project_id" = "public"."get_my_employee_project_id"())))) WITH CHECK (("public"."is_management"() OR ("public"."is_planner"() AND ("project_id" = "public"."get_my_employee_project_id"()))));



ALTER TABLE "public"."interview_invites" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "interview_invites_read" ON "public"."interview_invites" FOR SELECT TO "authenticated" USING (("public"."is_admin"() OR "public"."is_planner"()));



ALTER TABLE "public"."kb_chunks" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "kb_chunks_sel" ON "public"."kb_chunks" FOR SELECT USING ((COALESCE((("public"."perm"("auth"."uid"(), 'wissen'::"text") ->> 'visible'::"text"))::boolean, false) AND "public"."perm_proj_ok"("auth"."uid"(), 'wissen'::"text", "project_id")));



CREATE POLICY "kb_chunks_write" ON "public"."kb_chunks" USING ((("public"."perm_mode"("auth"."uid"(), 'wissen'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'wissen'::"text", "project_id"))) WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'wissen'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'wissen'::"text", "project_id")));



ALTER TABLE "public"."kb_documents" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "kb_documents_sel" ON "public"."kb_documents" FOR SELECT USING ((COALESCE((("public"."perm"("auth"."uid"(), 'wissen'::"text") ->> 'visible'::"text"))::boolean, false) AND "public"."perm_proj_ok"("auth"."uid"(), 'wissen'::"text", "project_id")));



CREATE POLICY "kb_documents_write" ON "public"."kb_documents" USING ((("public"."perm_mode"("auth"."uid"(), 'wissen'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'wissen'::"text", "project_id"))) WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'wissen'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'wissen'::"text", "project_id")));



ALTER TABLE "public"."kb_facts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "kb_facts_sel" ON "public"."kb_facts" FOR SELECT USING ((COALESCE((("public"."perm"("auth"."uid"(), 'wissen'::"text") ->> 'visible'::"text"))::boolean, false) AND "public"."perm_proj_ok"("auth"."uid"(), 'wissen'::"text", "project_id")));



CREATE POLICY "kb_facts_write" ON "public"."kb_facts" USING ((("public"."perm_mode"("auth"."uid"(), 'wissen'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'wissen'::"text", "project_id"))) WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'wissen'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'wissen'::"text", "project_id")));



ALTER TABLE "public"."kb_queries" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "kb_queries_sel" ON "public"."kb_queries" FOR SELECT USING ((COALESCE((("public"."perm"("auth"."uid"(), 'wissen'::"text") ->> 'visible'::"text"))::boolean, false) AND "public"."perm_proj_ok"("auth"."uid"(), 'wissen'::"text", "project_id")));



ALTER TABLE "public"."kb_regions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "kb_regions_sel" ON "public"."kb_regions" FOR SELECT USING ((COALESCE((("public"."perm"("auth"."uid"(), 'wissen'::"text") ->> 'visible'::"text"))::boolean, false) AND "public"."perm_proj_ok"("auth"."uid"(), 'wissen'::"text", "project_id")));



CREATE POLICY "kb_regions_write" ON "public"."kb_regions" USING ((("public"."perm_mode"("auth"."uid"(), 'wissen'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'wissen'::"text", "project_id"))) WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'wissen'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'wissen'::"text", "project_id")));



CREATE POLICY "ke_perm_delete" ON "public"."kpi_entries" FOR DELETE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'kpi'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'kpi'::"text", ( SELECT "e"."project_id"
   FROM "public"."employees" "e"
  WHERE ("e"."id" = "kpi_entries"."emp_id")), NULL::"text")));



CREATE POLICY "ke_perm_insert" ON "public"."kpi_entries" FOR INSERT TO "authenticated" WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'kpi'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'kpi'::"text", ( SELECT "e"."project_id"
   FROM "public"."employees" "e"
  WHERE ("e"."id" = "kpi_entries"."emp_id")), NULL::"text")));



CREATE POLICY "ke_perm_select" ON "public"."kpi_entries" FOR SELECT TO "authenticated" USING ((("emp_id" = "public"."perm_caller_emp_id"()) OR (("public"."perm_mode"("auth"."uid"(), 'kpi'::"text") <> 'none'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'kpi'::"text", ( SELECT "e"."project_id"
   FROM "public"."employees" "e"
  WHERE ("e"."id" = "kpi_entries"."emp_id")), NULL::"text"))));



CREATE POLICY "ke_perm_update" ON "public"."kpi_entries" FOR UPDATE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'kpi'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'kpi'::"text", ( SELECT "e"."project_id"
   FROM "public"."employees" "e"
  WHERE ("e"."id" = "kpi_entries"."emp_id")), NULL::"text"))) WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'kpi'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'kpi'::"text", ( SELECT "e"."project_id"
   FROM "public"."employees" "e"
  WHERE ("e"."id" = "kpi_entries"."emp_id")), NULL::"text")));



CREATE POLICY "kpe_perm_delete" ON "public"."kpi_project_entries" FOR DELETE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'kpi'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'kpi'::"text", "project_id", NULL::"text")));



CREATE POLICY "kpe_perm_insert" ON "public"."kpi_project_entries" FOR INSERT TO "authenticated" WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'kpi'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'kpi'::"text", "project_id", NULL::"text")));



CREATE POLICY "kpe_perm_select" ON "public"."kpi_project_entries" FOR SELECT TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'kpi'::"text") <> 'none'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'kpi'::"text", "project_id", NULL::"text")));



CREATE POLICY "kpe_perm_update" ON "public"."kpi_project_entries" FOR UPDATE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'kpi'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'kpi'::"text", "project_id", NULL::"text"))) WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'kpi'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'kpi'::"text", "project_id", NULL::"text")));



ALTER TABLE "public"."kpi_config" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "kpi_config HR write" ON "public"."kpi_config" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"]))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



CREATE POLICY "kpi_config read internal" ON "public"."kpi_config" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text", 'teamlead'::"text", 'projektleiter'::"text", 'mitarbeiter'::"text"])))));



ALTER TABLE "public"."kpi_entries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."kpi_project_entries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."lead_import_state" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "lead_import_state_rw" ON "public"."lead_import_state" TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



ALTER TABLE "public"."leader_nudge_prompts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "lnp_read" ON "public"."leader_nudge_prompts" FOR SELECT USING ("public"."is_management"());



CREATE POLICY "lnp_write" ON "public"."leader_nudge_prompts" USING ("public"."is_management"()) WITH CHECK ("public"."is_management"());



ALTER TABLE "public"."location_monthly" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "location_monthly HR write" ON "public"."location_monthly" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"]))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



CREATE POLICY "location_monthly read internal" ON "public"."location_monthly" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text", 'teamlead'::"text", 'projektleiter'::"text", 'mitarbeiter'::"text"])))));



ALTER TABLE "public"."locations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "locations HR write" ON "public"."locations" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"]))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



CREATE POLICY "locations read internal" ON "public"."locations" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text", 'teamlead'::"text", 'projektleiter'::"text", 'mitarbeiter'::"text"])))));



ALTER TABLE "public"."mail_attachments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."mail_conversation_meta" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."mail_folders" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."mail_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."mail_senders" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "mail_senders_sel" ON "public"."mail_senders" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "mail_senders_write" ON "public"."mail_senders" TO "authenticated" USING ("public"."is_management"()) WITH CHECK ("public"."is_management"());



ALTER TABLE "public"."mail_tags" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."mail_templates" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "mail_templates_sel" ON "public"."mail_templates" FOR SELECT TO "authenticated" USING ("public"."is_management"());



CREATE POLICY "mail_templates_write" ON "public"."mail_templates" TO "authenticated" USING ("public"."is_management"()) WITH CHECK ("public"."is_management"());



CREATE POLICY "mailatt_select" ON "public"."mail_attachments" FOR SELECT TO "authenticated" USING (("public"."is_management"() OR "public"."is_hr"()));



CREATE POLICY "mconvmeta_all" ON "public"."mail_conversation_meta" TO "authenticated" USING (("public"."is_management"() OR "public"."is_hr"())) WITH CHECK (("public"."is_management"() OR "public"."is_hr"()));



ALTER TABLE "public"."meeting_note_comments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "meeting_note_comments_delete" ON "public"."meeting_note_comments" FOR DELETE TO "authenticated" USING ("public"."mn_can_write"("project_id"));



CREATE POLICY "meeting_note_comments_insert" ON "public"."meeting_note_comments" FOR INSERT TO "authenticated" WITH CHECK (("public"."mn_can_read"("project_id") AND ("created_by" = "auth"."uid"())));



CREATE POLICY "meeting_note_comments_manage" ON "public"."meeting_note_comments" FOR UPDATE TO "authenticated" USING ("public"."mn_can_write"("project_id")) WITH CHECK ("public"."mn_can_write"("project_id"));



CREATE POLICY "meeting_note_comments_read" ON "public"."meeting_note_comments" FOR SELECT TO "authenticated" USING ("public"."mn_can_read"("project_id"));



ALTER TABLE "public"."meeting_note_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "meeting_note_items_read" ON "public"."meeting_note_items" FOR SELECT TO "authenticated" USING ("public"."mn_can_read"("project_id"));



CREATE POLICY "meeting_note_items_write" ON "public"."meeting_note_items" TO "authenticated" USING ("public"."mn_can_write"("project_id")) WITH CHECK ("public"."mn_can_write"("project_id"));



ALTER TABLE "public"."meeting_notes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "meeting_notes_read" ON "public"."meeting_notes" FOR SELECT TO "authenticated" USING ("public"."mn_can_read"("project_id"));



CREATE POLICY "meeting_notes_write" ON "public"."meeting_notes" TO "authenticated" USING ("public"."mn_can_write"("project_id")) WITH CHECK ("public"."mn_can_write"("project_id"));



CREATE POLICY "mfolders_all" ON "public"."mail_folders" TO "authenticated" USING (("public"."is_management"() OR "public"."is_hr"())) WITH CHECK (("public"."is_management"() OR "public"."is_hr"()));



ALTER TABLE "public"."mgmt_call_access" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "mgmt_call_access_mc" ON "public"."mgmt_call_access" TO "authenticated" USING ("public"."is_mgmt_call_user"()) WITH CHECK ("public"."is_mgmt_call_user"());



ALTER TABLE "public"."mgmt_call_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "mgmt_call_items_mc" ON "public"."mgmt_call_items" TO "authenticated" USING ("public"."is_mgmt_call_user"()) WITH CHECK ("public"."is_mgmt_call_user"());



ALTER TABLE "public"."mgmt_calls" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "mgmt_calls_mc" ON "public"."mgmt_calls" TO "authenticated" USING ("public"."is_mgmt_call_user"()) WITH CHECK ("public"."is_mgmt_call_user"());



ALTER TABLE "public"."mgmt_task_out" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "mgmt_task_out_assignee_sel" ON "public"."mgmt_task_out" FOR SELECT TO "authenticated" USING (("assignee_user" = "auth"."uid"()));



CREATE POLICY "mgmt_task_out_assignee_upd" ON "public"."mgmt_task_out" FOR UPDATE TO "authenticated" USING (("assignee_user" = "auth"."uid"())) WITH CHECK (("assignee_user" = "auth"."uid"()));



CREATE POLICY "mgmt_task_out_mgmt" ON "public"."mgmt_task_out" TO "authenticated" USING ("public"."is_mgmt_call_user"()) WITH CHECK ("public"."is_mgmt_call_user"());



CREATE POLICY "mm_select" ON "public"."mail_messages" FOR SELECT TO "authenticated" USING (("public"."is_management"() OR ("public"."is_hr"() AND (NOT (("employee_id" IS NOT NULL) AND "public"."is_protected_employee"("employee_id")))) OR (("cv_id" IS NOT NULL) AND ("public"."perm_mode"("auth"."uid"(), 'bewerber'::"text") <> 'none'::"text")) OR (("employee_id" IS NOT NULL) AND ("employee_id" = "public"."perm_caller_emp_id"()))));



CREATE POLICY "mm_update" ON "public"."mail_messages" FOR UPDATE TO "authenticated" USING (("public"."is_management"() OR ("public"."is_hr"() AND (NOT (("employee_id" IS NOT NULL) AND "public"."is_protected_employee"("employee_id")))))) WITH CHECK (("public"."is_management"() OR ("public"."is_hr"() AND (NOT (("employee_id" IS NOT NULL) AND "public"."is_protected_employee"("employee_id"))))));



CREATE POLICY "mtags_all" ON "public"."mail_tags" TO "authenticated" USING (("public"."is_management"() OR "public"."is_hr"())) WITH CHECK (("public"."is_management"() OR "public"."is_hr"()));



ALTER TABLE "public"."notify_prefs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "notify_prefs_sel" ON "public"."notify_prefs" FOR SELECT TO "authenticated" USING ("public"."is_planner"());



CREATE POLICY "notify_prefs_write" ON "public"."notify_prefs" TO "authenticated" USING ("public"."is_management"()) WITH CHECK ("public"."is_management"());



ALTER TABLE "public"."org_nodes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "org_nodes HR write" ON "public"."org_nodes" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"]))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



CREATE POLICY "org_nodes read internal" ON "public"."org_nodes" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text", 'teamlead'::"text", 'projektleiter'::"text", 'mitarbeiter'::"text"])))));



ALTER TABLE "public"."partner_agents" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "partner_agents_sel" ON "public"."partner_agents" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "partner_agents_write" ON "public"."partner_agents" USING ("public"."is_management"()) WITH CHECK ("public"."is_management"());



ALTER TABLE "public"."payroll_inputs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."payslips" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."permission_areas" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "permission_areas_read" ON "public"."permission_areas" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "pi_perm_delete" ON "public"."payroll_inputs" FOR DELETE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'lohn'::"text") = 'edit'::"text") AND ((NOT "public"."is_protected_employee"("emp_id")) OR "public"."is_management"() OR "public"."is_finance"())));



CREATE POLICY "pi_perm_insert" ON "public"."payroll_inputs" FOR INSERT TO "authenticated" WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'lohn'::"text") = 'edit'::"text") AND ((NOT "public"."is_protected_employee"("emp_id")) OR "public"."is_management"() OR "public"."is_finance"())));



CREATE POLICY "pi_perm_select" ON "public"."payroll_inputs" FOR SELECT TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'lohn'::"text") <> 'none'::"text") AND ((NOT "public"."is_protected_employee"("emp_id")) OR "public"."is_management"() OR "public"."is_finance"())));



CREATE POLICY "pi_perm_update" ON "public"."payroll_inputs" FOR UPDATE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'lohn'::"text") = 'edit'::"text") AND ((NOT "public"."is_protected_employee"("emp_id")) OR "public"."is_management"() OR "public"."is_finance"()))) WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'lohn'::"text") = 'edit'::"text") AND ((NOT "public"."is_protected_employee"("emp_id")) OR "public"."is_management"() OR "public"."is_finance"())));



CREATE POLICY "pres_comments_client_insert" ON "public"."presentation_comments" FOR INSERT TO "authenticated" WITH CHECK ((("project_id" = "public"."get_my_client_project_id"()) AND ("created_by" = "auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM "public"."presentations" "p"
  WHERE (("p"."id" = "presentation_comments"."presentation_id") AND ("p"."published" = true) AND ("p"."project_id" = "p"."project_id"))))));



CREATE POLICY "pres_comments_client_read" ON "public"."presentation_comments" FOR SELECT TO "authenticated" USING (("project_id" = "public"."get_my_client_project_id"()));



CREATE POLICY "pres_comments_mgmt_all" ON "public"."presentation_comments" TO "authenticated" USING (("public"."is_management"() OR ("public"."is_planner"() AND ("project_id" = "public"."get_my_employee_project_id"())))) WITH CHECK (("public"."is_management"() OR ("public"."is_planner"() AND ("project_id" = "public"."get_my_employee_project_id"()))));



ALTER TABLE "public"."presentation_comments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."presentation_templates" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "presentation_templates_admin_all" ON "public"."presentation_templates" TO "authenticated" USING ("public"."is_management"()) WITH CHECK ("public"."is_management"());



CREATE POLICY "presentation_templates_planner_read" ON "public"."presentation_templates" FOR SELECT TO "authenticated" USING ("public"."is_planner"());



ALTER TABLE "public"."presentations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "presentations_admin_all" ON "public"."presentations" TO "authenticated" USING ("public"."is_management"()) WITH CHECK ("public"."is_management"());



CREATE POLICY "presentations_client_read" ON "public"."presentations" FOR SELECT TO "authenticated" USING ((("published" = true) AND ("project_id" = "public"."get_my_client_project_id"())));



CREATE POLICY "presentations_mgmt_all" ON "public"."presentations" TO "authenticated" USING (("public"."is_management"() OR ("public"."is_planner"() AND ("project_id" = "public"."get_my_employee_project_id"())))) WITH CHECK (("public"."is_management"() OR ("public"."is_planner"() AND ("project_id" = "public"."get_my_employee_project_id"()))));



ALTER TABLE "public"."project_skill_profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "project_skill_profiles HR write" ON "public"."project_skill_profiles" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"]))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



CREATE POLICY "project_skill_profiles read internal" ON "public"."project_skill_profiles" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text", 'teamlead'::"text", 'projektleiter'::"text", 'mitarbeiter'::"text"])))));



ALTER TABLE "public"."project_skills" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "project_skills HR write" ON "public"."project_skills" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"]))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



CREATE POLICY "project_skills read internal" ON "public"."project_skills" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text", 'teamlead'::"text", 'projektleiter'::"text", 'mitarbeiter'::"text"])))));



ALTER TABLE "public"."project_trainings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "project_trainings HR write" ON "public"."project_trainings" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"]))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



CREATE POLICY "project_trainings read internal" ON "public"."project_trainings" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text", 'teamlead'::"text", 'projektleiter'::"text", 'mitarbeiter'::"text"])))));



ALTER TABLE "public"."projects" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "projects HR write" ON "public"."projects" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"]))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



CREATE POLICY "projects read internal" ON "public"."projects" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text", 'teamlead'::"text", 'projektleiter'::"text", 'mitarbeiter'::"text"])))));



CREATE POLICY "ps_perm_delete" ON "public"."payslips" FOR DELETE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'lohn'::"text") = 'edit'::"text") AND ((NOT "public"."is_protected_employee"("employee_id")) OR "public"."is_management"() OR "public"."is_finance"())));



CREATE POLICY "ps_perm_insert" ON "public"."payslips" FOR INSERT TO "authenticated" WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'lohn'::"text") = 'edit'::"text") AND ((NOT "public"."is_protected_employee"("employee_id")) OR "public"."is_management"() OR "public"."is_finance"())));



CREATE POLICY "ps_perm_select" ON "public"."payslips" FOR SELECT TO "authenticated" USING ((("employee_id" = "public"."perm_caller_emp_id"()) OR (("public"."perm_mode"("auth"."uid"(), 'lohn'::"text") <> 'none'::"text") AND ((NOT "public"."is_protected_employee"("employee_id")) OR "public"."is_management"() OR "public"."is_finance"()))));



CREATE POLICY "ps_perm_update" ON "public"."payslips" FOR UPDATE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'lohn'::"text") = 'edit'::"text") AND ((NOT "public"."is_protected_employee"("employee_id")) OR "public"."is_management"() OR "public"."is_finance"()))) WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'lohn'::"text") = 'edit'::"text") AND ((NOT "public"."is_protected_employee"("employee_id")) OR "public"."is_management"() OR "public"."is_finance"())));



ALTER TABLE "public"."reminder_schedule" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."report_forecast" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."report_fte" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "report_fte_mgmt" ON "public"."report_fte" TO "authenticated" USING (("public"."is_management"() OR ("public"."is_planner"() AND ("project_id" = "public"."get_my_employee_project_id"())))) WITH CHECK (("public"."is_management"() OR ("public"."is_planner"() AND ("project_id" = "public"."get_my_employee_project_id"()))));



ALTER TABLE "public"."report_longterm" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "report_longterm_mgmt" ON "public"."report_longterm" TO "authenticated" USING (("public"."is_management"() OR ("public"."is_planner"() AND ("project_id" = "public"."get_my_employee_project_id"())))) WITH CHECK (("public"."is_management"() OR ("public"."is_planner"() AND ("project_id" = "public"."get_my_employee_project_id"()))));



ALTER TABLE "public"."report_measures" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "report_measures_mgmt" ON "public"."report_measures" TO "authenticated" USING (("public"."is_management"() OR ("public"."is_planner"() AND ("project_id" = "public"."get_my_employee_project_id"())))) WITH CHECK (("public"."is_management"() OR ("public"."is_planner"() AND ("project_id" = "public"."get_my_employee_project_id"()))));



CREATE POLICY "rf_perm_delete" ON "public"."report_forecast" FOR DELETE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'praesent'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'praesent'::"text", "project_id", NULL::"text")));



CREATE POLICY "rf_perm_insert" ON "public"."report_forecast" FOR INSERT TO "authenticated" WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'praesent'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'praesent'::"text", "project_id", NULL::"text")));



CREATE POLICY "rf_perm_select" ON "public"."report_forecast" FOR SELECT TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'praesent'::"text") <> 'none'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'praesent'::"text", "project_id", NULL::"text")));



CREATE POLICY "rf_perm_update" ON "public"."report_forecast" FOR UPDATE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'praesent'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'praesent'::"text", "project_id", NULL::"text"))) WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'praesent'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'praesent'::"text", "project_id", NULL::"text")));



ALTER TABLE "public"."rk_monthly" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "rk_monthly HR write" ON "public"."rk_monthly" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"]))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



CREATE POLICY "rk_monthly read internal" ON "public"."rk_monthly" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



ALTER TABLE "public"."rk_overhead" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "rk_overhead HR write" ON "public"."rk_overhead" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"]))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



CREATE POLICY "rk_overhead read internal" ON "public"."rk_overhead" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



ALTER TABLE "public"."role_permissions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "role_permissions_mgmt" ON "public"."role_permissions" USING ("public"."is_management"()) WITH CHECK ("public"."is_management"());



ALTER TABLE "public"."roles_definitions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "roles_definitions_select" ON "public"."roles_definitions" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "rs_read" ON "public"."reminder_schedule" FOR SELECT USING ("public"."is_management"());



CREATE POLICY "rs_write" ON "public"."reminder_schedule" USING ("public"."is_management"()) WITH CHECK ("public"."is_management"());



CREATE POLICY "sa_perm_delete" ON "public"."shift_assignments" FOR DELETE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text")));



CREATE POLICY "sa_perm_insert" ON "public"."shift_assignments" FOR INSERT TO "authenticated" WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text")));



CREATE POLICY "sa_perm_select" ON "public"."shift_assignments" FOR SELECT TO "authenticated" USING ((("employee_id" = "public"."perm_caller_emp_id"()) OR (("public"."perm_mode"("auth"."uid"(), 'shift'::"text") <> 'none'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text"))));



CREATE POLICY "sa_perm_update" ON "public"."shift_assignments" FOR UPDATE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text"))) WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text")));



ALTER TABLE "public"."sales_access" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_access_sales" ON "public"."sales_access" TO "authenticated" USING ("public"."is_sales_user"()) WITH CHECK ("public"."is_sales_user"());



ALTER TABLE "public"."sales_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_events_sales" ON "public"."sales_events" TO "authenticated" USING ("public"."is_sales_user"()) WITH CHECK ("public"."is_sales_user"());



ALTER TABLE "public"."sales_leads" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_leads_sales" ON "public"."sales_leads" TO "authenticated" USING ("public"."is_sales_user"()) WITH CHECK ("public"."is_sales_user"());



ALTER TABLE "public"."sales_suppression" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_suppression_sales" ON "public"."sales_suppression" TO "authenticated" USING ("public"."is_sales_user"()) WITH CHECK ("public"."is_sales_user"());



ALTER TABLE "public"."sales_templates" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_templates_sales" ON "public"."sales_templates" TO "authenticated" USING ("public"."is_sales_user"()) WITH CHECK ("public"."is_sales_user"());



ALTER TABLE "public"."sales_upload_maps" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_upload_maps_rw" ON "public"."sales_upload_maps" USING ("public"."is_sales_user"()) WITH CHECK ("public"."is_sales_user"());



CREATE POLICY "sc_perm_delete" ON "public"."shift_checkins" FOR DELETE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text")));



CREATE POLICY "sc_perm_insert" ON "public"."shift_checkins" FOR INSERT TO "authenticated" WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text")));



CREATE POLICY "sc_perm_select" ON "public"."shift_checkins" FOR SELECT TO "authenticated" USING ((("employee_id" = "public"."perm_caller_emp_id"()) OR (("public"."perm_mode"("auth"."uid"(), 'shift'::"text") <> 'none'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text"))));



CREATE POLICY "sc_perm_update" ON "public"."shift_checkins" FOR UPDATE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text"))) WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text")));



ALTER TABLE "public"."shift_assignments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."shift_checkins" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."showcases" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."spaces" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "spaces HR write" ON "public"."spaces" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"]))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



CREATE POLICY "spaces read internal" ON "public"."spaces" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text", 'teamlead'::"text", 'projektleiter'::"text", 'mitarbeiter'::"text"])))));



ALTER TABLE "public"."system_findings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "system_findings_read" ON "public"."system_findings" FOR SELECT USING ("public"."is_management"());



ALTER TABLE "public"."task_assignments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "task_assignments_sel" ON "public"."task_assignments" FOR SELECT TO "authenticated" USING ("public"."is_planner"());



CREATE POLICY "task_assignments_write" ON "public"."task_assignments" TO "authenticated" USING ("public"."is_management"()) WITH CHECK ("public"."is_management"());



ALTER TABLE "public"."task_catalog" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "task_catalog_sel" ON "public"."task_catalog" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "task_catalog_write" ON "public"."task_catalog" TO "authenticated" USING ("public"."is_management"()) WITH CHECK ("public"."is_management"());



ALTER TABLE "public"."task_snooze" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "task_snooze_own" ON "public"."task_snooze" TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."task_takeover" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "task_takeover_sel" ON "public"."task_takeover" FOR SELECT TO "authenticated" USING ("public"."is_planner"());



ALTER TABLE "public"."time_pin_attempts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."time_pins" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "time_pins HR access" ON "public"."time_pins" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"]))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



ALTER TABLE "public"."time_sessions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "time_sessions HR write" ON "public"."time_sessions" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"]))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



CREATE POLICY "time_sessions read internal" ON "public"."time_sessions" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text", 'teamlead'::"text", 'projektleiter'::"text"])))));



CREATE POLICY "time_sessions self read" ON "public"."time_sessions" FOR SELECT TO "authenticated" USING (("emp_id" = ( SELECT "app_users"."employee_id"
   FROM "public"."app_users"
  WHERE ("app_users"."user_id" = "auth"."uid"()))));



ALTER TABLE "public"."training_plans" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "training_plans HR write" ON "public"."training_plans" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"]))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



CREATE POLICY "training_plans read internal" ON "public"."training_plans" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text", 'teamlead'::"text", 'projektleiter'::"text", 'mitarbeiter'::"text"])))));



CREATE POLICY "training_plans_planner" ON "public"."training_plans" USING ((("public"."perm_mode"("auth"."uid"(), 'schulung'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'schulung'::"text", "project_id", NULL::"text"))) WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'schulung'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'schulung'::"text", "project_id", NULL::"text")));



CREATE POLICY "upload_owner_del" ON "public"."upload_project_owner" FOR DELETE TO "authenticated" USING ("public"."is_management"());



CREATE POLICY "upload_owner_ins" ON "public"."upload_project_owner" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_management"());



CREATE POLICY "upload_owner_sel" ON "public"."upload_project_owner" FOR SELECT TO "authenticated" USING (("public"."is_management"() OR ("project_id" = "public"."get_my_employee_project_id"())));



CREATE POLICY "upload_owner_upd" ON "public"."upload_project_owner" FOR UPDATE TO "authenticated" USING ("public"."is_management"()) WITH CHECK ("public"."is_management"());



ALTER TABLE "public"."upload_project_owner" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."upload_schedule" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "upload_schedule_del" ON "public"."upload_schedule" FOR DELETE TO "authenticated" USING ("public"."is_management"());



CREATE POLICY "upload_schedule_ins" ON "public"."upload_schedule" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_management"());



CREATE POLICY "upload_schedule_sel" ON "public"."upload_schedule" FOR SELECT TO "authenticated" USING (("public"."is_management"() OR ("project_id" = "public"."get_my_employee_project_id"())));



CREATE POLICY "upload_schedule_upd" ON "public"."upload_schedule" FOR UPDATE TO "authenticated" USING ("public"."is_management"()) WITH CHECK ("public"."is_management"());



ALTER TABLE "public"."usage_digests" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "usage_digests_sel" ON "public"."usage_digests" FOR SELECT TO "authenticated" USING ("public"."is_management"());



ALTER TABLE "public"."user_permissions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_permissions_mgmt" ON "public"."user_permissions" USING ("public"."is_management"()) WITH CHECK ("public"."is_management"());



ALTER TABLE "public"."user_prefs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_prefs_own" ON "public"."user_prefs" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."user_sessions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_sessions_sel" ON "public"."user_sessions" FOR SELECT TO "authenticated" USING ("public"."is_management"());



CREATE POLICY "va_perm_delete" ON "public"."vacation_accounts" FOR DELETE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'lohn'::"text") = 'edit'::"text") AND (NOT "public"."is_finance"()) AND ((NOT "public"."is_protected_employee"("employee_id")) OR "public"."is_management"())));



CREATE POLICY "va_perm_insert" ON "public"."vacation_accounts" FOR INSERT TO "authenticated" WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'lohn'::"text") = 'edit'::"text") AND (NOT "public"."is_finance"()) AND ((NOT "public"."is_protected_employee"("employee_id")) OR "public"."is_management"())));



CREATE POLICY "va_perm_select" ON "public"."vacation_accounts" FOR SELECT TO "authenticated" USING ((("employee_id" = "public"."perm_caller_emp_id"()) OR (("public"."perm_mode"("auth"."uid"(), 'lohn'::"text") <> 'none'::"text") AND (NOT "public"."is_finance"()) AND ((NOT "public"."is_protected_employee"("employee_id")) OR "public"."is_management"()))));



CREATE POLICY "va_perm_update" ON "public"."vacation_accounts" FOR UPDATE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'lohn'::"text") = 'edit'::"text") AND (NOT "public"."is_finance"()) AND ((NOT "public"."is_protected_employee"("employee_id")) OR "public"."is_management"()))) WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'lohn'::"text") = 'edit'::"text") AND (NOT "public"."is_finance"()) AND ((NOT "public"."is_protected_employee"("employee_id")) OR "public"."is_management"())));



ALTER TABLE "public"."vacation_accounts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."vacation_requests" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "vacreq MA delete own pending" ON "public"."vacation_requests" FOR DELETE TO "authenticated" USING ((("employee_id" = "public"."get_my_employee_id"()) AND ("status" = 'pending'::"text")));



CREATE POLICY "vacreq MA insert own" ON "public"."vacation_requests" FOR INSERT TO "authenticated" WITH CHECK ((("employee_id" = "public"."get_my_employee_id"()) AND ("status" = 'pending'::"text")));



CREATE POLICY "vacreq_perm_select" ON "public"."vacation_requests" FOR SELECT TO "authenticated" USING ((("employee_id" = "public"."perm_caller_emp_id"()) OR (("public"."perm_mode"("auth"."uid"(), 'absence'::"text") <> 'none'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'absence'::"text", ( SELECT "e"."project_id"
   FROM "public"."employees" "e"
  WHERE ("e"."id" = "vacation_requests"."employee_id")), NULL::"text"))));



CREATE POLICY "vacreq_perm_update" ON "public"."vacation_requests" FOR UPDATE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'absence'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'absence'::"text", ( SELECT "e"."project_id"
   FROM "public"."employees" "e"
  WHERE ("e"."id" = "vacation_requests"."employee_id")), NULL::"text"))) WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'absence'::"text") = 'edit'::"text") AND "public"."perm_proj_ok"("auth"."uid"(), 'absence'::"text", ( SELECT "e"."project_id"
   FROM "public"."employees" "e"
  WHERE ("e"."id" = "vacation_requests"."employee_id")), NULL::"text")));



ALTER TABLE "public"."vorort_attempts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."weekly_calls" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "weekly_calls_mgmt" ON "public"."weekly_calls" TO "authenticated" USING (("public"."is_management"() OR ("public"."is_planner"() AND ("project_id" = "public"."get_my_employee_project_id"())))) WITH CHECK (("public"."is_management"() OR ("public"."is_planner"() AND ("project_id" = "public"."get_my_employee_project_id"()))));



ALTER TABLE "public"."weekly_gauges" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "weekly_gauges_mgmt" ON "public"."weekly_gauges" TO "authenticated" USING (("public"."is_management"() OR ("public"."is_planner"() AND ("project_id" = "public"."get_my_employee_project_id"())))) WITH CHECK (("public"."is_management"() OR ("public"."is_planner"() AND ("project_id" = "public"."get_my_employee_project_id"()))));



ALTER TABLE "public"."weekly_hours_legacy" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "wh_perm_delete" ON "public"."weekly_hours_legacy" FOR DELETE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") = 'edit'::"text") AND (NOT "public"."is_hr"()) AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text")));



CREATE POLICY "wh_perm_insert" ON "public"."weekly_hours_legacy" FOR INSERT TO "authenticated" WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") = 'edit'::"text") AND (NOT "public"."is_hr"()) AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text")));



CREATE POLICY "wh_perm_select" ON "public"."weekly_hours_legacy" FOR SELECT TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") <> 'none'::"text") AND (NOT "public"."is_hr"()) AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text")));



CREATE POLICY "wh_perm_update" ON "public"."weekly_hours_legacy" FOR UPDATE TO "authenticated" USING ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") = 'edit'::"text") AND (NOT "public"."is_hr"()) AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text"))) WITH CHECK ((("public"."perm_mode"("auth"."uid"(), 'shift'::"text") = 'edit'::"text") AND (NOT "public"."is_hr"()) AND "public"."perm_proj_ok"("auth"."uid"(), 'shift'::"text", "project_id", NULL::"text")));



ALTER TABLE "public"."wheel_budgets" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "wheel_budgets HR write" ON "public"."wheel_budgets" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"]))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



CREATE POLICY "wheel_budgets read internal" ON "public"."wheel_budgets" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text", 'teamlead'::"text", 'projektleiter'::"text", 'mitarbeiter'::"text"])))));



ALTER TABLE "public"."wheel_specials" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "wheel_specials HR write" ON "public"."wheel_specials" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"]))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



CREATE POLICY "wheel_specials read internal" ON "public"."wheel_specials" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text", 'teamlead'::"text", 'projektleiter'::"text", 'mitarbeiter'::"text"])))));



ALTER TABLE "public"."wheel_spins" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "wheel_spins HR write" ON "public"."wheel_spins" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"]))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text"])))));



CREATE POLICY "wheel_spins read internal" ON "public"."wheel_spins" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_users"
  WHERE (("app_users"."user_id" = "auth"."uid"()) AND ("app_users"."role_keys" && ARRAY['management'::"text", 'hr'::"text", 'finance'::"text", 'teamlead'::"text", 'projektleiter'::"text"])))));



CREATE POLICY "wheel_spins self read" ON "public"."wheel_spins" FOR SELECT TO "authenticated" USING (("emp_id" = ( SELECT "app_users"."employee_id"
   FROM "public"."app_users"
  WHERE ("app_users"."user_id" = "auth"."uid"()))));



ALTER TABLE "public"."windsor_leads" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "windsor_leads_all" ON "public"."windsor_leads" TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



ALTER TABLE "public"."windsor_marketing" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "windsor_marketing_mgmt" ON "public"."windsor_marketing" FOR SELECT TO "authenticated" USING ("public"."is_management"());



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";
GRANT USAGE ON SCHEMA "public" TO "nlquery_ro";
GRANT USAGE ON SCHEMA "public" TO "agent_ro";



GRANT ALL ON FUNCTION "public"."agent_guard"("p_agent" "text", "p_action" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."agent_guard"("p_agent" "text", "p_action" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."agent_guard"("p_agent" "text", "p_action" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."agent_missing_bank_targets"("p_actor" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."agent_missing_bank_targets"("p_actor" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."agent_missing_bank_targets"("p_actor" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."agent_query_exec"("p_sql" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."agent_query_exec"("p_sql" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."agent_query_exec"("p_sql" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."agent_query_exec"("p_sql" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."agent_recipients"("p_project" "text", "p_area" "text", "p_roles" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."agent_recipients"("p_project" "text", "p_area" "text", "p_roles" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."agent_recipients"("p_project" "text", "p_area" "text", "p_roles" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_access_overview"() TO "anon";
GRANT ALL ON FUNCTION "public"."ai_access_overview"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_access_overview"() TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_allowed_projects"() TO "anon";
GRANT ALL ON FUNCTION "public"."ai_allowed_projects"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_allowed_projects"() TO "service_role";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."employees" TO "anon";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."employees" TO "authenticated";
GRANT ALL ON TABLE "public"."employees" TO "service_role";
GRANT SELECT ON TABLE "public"."employees" TO "agent_ro";



GRANT SELECT("id") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("first_name") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("last_name") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("email") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("phone") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("staff_number") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("role_keys") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("project_id") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("skill") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("target_role") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("status") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("source") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("cv_skills") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("hire_date") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("termination_date") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("location") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("photo_url") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("about_text") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("interests") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("notes") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("salary_type") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("work_model") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("work_hours") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("shift_earliest") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("shift_latest") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("vacation_days") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("absences") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("audios") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("videos") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("warnings") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("project_assignments") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("allowed_shifts") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("extra") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("created_at") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("updated_at") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("abilities") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("bonuses") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("referrals") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("quality_ratings") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("hardware") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("position") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("city") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("project_skill") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("primary_skill") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("photo_color") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("guaranteed_pct") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("deduct_missing") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("free_days_month") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("overtime_allowed") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("productive_pct") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("forecast_include") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("efficiency_override_pct") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("age") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("gender") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("education") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("education_level") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("experience_years") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("language_level") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("writing_level") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("languages_str") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("dream") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("hobbies") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("favorite_food") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("travel_wish") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("birthday") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("work_holidays") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("work_saturday") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("work_sunday") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("work_split") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("work_notes") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("training_id") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("staff_number_old") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("import_source") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("kpi_exempt") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("overhead_productive_pct") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("email_internal") ON TABLE "public"."employees" TO "authenticated";



GRANT SELECT("status_changed_at") ON TABLE "public"."employees" TO "authenticated";



GRANT ALL ON FUNCTION "public"."ai_caller_emp"() TO "anon";
GRANT ALL ON FUNCTION "public"."ai_caller_emp"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_caller_emp"() TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_caller_projects"() TO "anon";
GRANT ALL ON FUNCTION "public"."ai_caller_projects"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_caller_projects"() TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_caller_rank"() TO "anon";
GRANT ALL ON FUNCTION "public"."ai_caller_rank"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_caller_rank"() TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_caller_skills"() TO "anon";
GRANT ALL ON FUNCTION "public"."ai_caller_skills"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_caller_skills"() TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_can_query"() TO "anon";
GRANT ALL ON FUNCTION "public"."ai_can_query"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_can_query"() TO "service_role";
GRANT ALL ON FUNCTION "public"."ai_can_query"() TO "nlquery_ro";



GRANT ALL ON FUNCTION "public"."ai_current_uid"() TO "anon";
GRANT ALL ON FUNCTION "public"."ai_current_uid"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_current_uid"() TO "service_role";
GRANT ALL ON FUNCTION "public"."ai_current_uid"() TO "nlquery_ro";



GRANT ALL ON FUNCTION "public"."ai_default_prefs"("p_uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_default_prefs"("p_uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_default_prefs"("p_uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_effective_prefs"("p_uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_effective_prefs"("p_uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_effective_prefs"("p_uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_emp_row_ok"("p_emp_id" "uuid", "p_project" "text", "p_skill" "text", "p_position" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_emp_row_ok"("p_emp_id" "uuid", "p_project" "text", "p_skill" "text", "p_position" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_emp_row_ok"("p_emp_id" "uuid", "p_project" "text", "p_skill" "text", "p_position" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."ai_emp_row_ok"("p_emp_id" "uuid", "p_project" "text", "p_skill" "text", "p_position" "text") TO "nlquery_ro";



GRANT ALL ON FUNCTION "public"."ai_full"() TO "anon";
GRANT ALL ON FUNCTION "public"."ai_full"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_full"() TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_is_full"("p_uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_is_full"("p_uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_is_full"("p_uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_position_category"("p" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_position_category"("p" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_position_category"("p" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_position_rank"("p_pos" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_position_rank"("p_pos" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_position_rank"("p_pos" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_prefs"() TO "anon";
GRANT ALL ON FUNCTION "public"."ai_prefs"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_prefs"() TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_proj_ok"("p_project" "text", "p_skill" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_proj_ok"("p_project" "text", "p_skill" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_proj_ok"("p_project" "text", "p_skill" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."ai_proj_ok"("p_project" "text", "p_skill" "text") TO "nlquery_ro";



GRANT ALL ON FUNCTION "public"."ai_salary_ok"("p_project" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_salary_ok"("p_project" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_salary_ok"("p_project" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."ai_scope_overview"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ai_scope_overview"() TO "anon";
GRANT ALL ON FUNCTION "public"."ai_scope_overview"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_scope_overview"() TO "service_role";



GRANT ALL ON FUNCTION "public"."ai_uid"() TO "anon";
GRANT ALL ON FUNCTION "public"."ai_uid"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_uid"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."auto_checkout_daily"("target" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."auto_checkout_daily"("target" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."auto_checkout_daily"("target" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_checkout_daily"("target" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."calendar_event_visible"("ev" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."calendar_event_visible"("ev" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calendar_event_visible"("ev" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."chat_is_monitored"("p_emp" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."chat_is_monitored"("p_emp" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."chat_is_monitored"("p_emp" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."chat_is_monitored"("p_emp" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."chat_monitoring_status"() TO "anon";
GRANT ALL ON FUNCTION "public"."chat_monitoring_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."chat_monitoring_status"() TO "service_role";



GRANT ALL ON FUNCTION "public"."clara_handover_scan"() TO "anon";
GRANT ALL ON FUNCTION "public"."clara_handover_scan"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."clara_handover_scan"() TO "service_role";



GRANT ALL ON FUNCTION "public"."clara_marketing_scan"() TO "anon";
GRANT ALL ON FUNCTION "public"."clara_marketing_scan"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."clara_marketing_scan"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."clara_morning_stats"("p_date" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."clara_morning_stats"("p_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."clara_morning_stats"("p_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."clara_morning_stats"("p_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."clara_schedule_rejection"() TO "anon";
GRANT ALL ON FUNCTION "public"."clara_schedule_rejection"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."clara_schedule_rejection"() TO "service_role";



GRANT ALL ON FUNCTION "public"."clara_workdays_since"("p_ts" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."clara_workdays_since"("p_ts" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."clara_workdays_since"("p_ts" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."clear_must_change_pw"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."clear_must_change_pw"() TO "anon";
GRANT ALL ON FUNCTION "public"."clear_must_change_pw"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."clear_must_change_pw"() TO "service_role";



GRANT ALL ON FUNCTION "public"."client_meeting_prep"("p_project" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."client_meeting_prep"("p_project" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."client_meeting_prep"("p_project" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."confirm_interview_slot"("p_token" "text", "p_slot" "text", "p_form" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."confirm_interview_slot"("p_token" "text", "p_slot" "text", "p_form" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."confirm_interview_slot"("p_token" "text", "p_slot" "text", "p_form" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_cv_enrich_invite"("p_cv_id" "uuid", "p_form_id" "uuid", "p_reusable" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."create_cv_enrich_invite"("p_cv_id" "uuid", "p_form_id" "uuid", "p_reusable" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_cv_enrich_invite"("p_cv_id" "uuid", "p_form_id" "uuid", "p_reusable" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."create_interview_invite"("p_cv_id" "uuid", "p_participant_ids" "uuid"[], "p_forms" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."create_interview_invite"("p_cv_id" "uuid", "p_participant_ids" "uuid"[], "p_forms" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_interview_invite"("p_cv_id" "uuid", "p_participant_ids" "uuid"[], "p_forms" "text"[]) TO "service_role";



GRANT ALL ON TABLE "public"."cvs" TO "anon";
GRANT ALL ON TABLE "public"."cvs" TO "authenticated";
GRANT ALL ON TABLE "public"."cvs" TO "service_role";
GRANT SELECT ON TABLE "public"."cvs" TO "agent_ro";



REVOKE ALL ON FUNCTION "public"."cv_public_json"("c" "public"."cvs", "p_visible" "text"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cv_public_json"("c" "public"."cvs", "p_visible" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."cv_public_json"("c" "public"."cvs", "p_visible" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cv_public_json"("c" "public"."cvs", "p_visible" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."cvs_assign_public_code"() TO "anon";
GRANT ALL ON FUNCTION "public"."cvs_assign_public_code"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cvs_assign_public_code"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cvs_guard_employee_dup"() TO "anon";
GRANT ALL ON FUNCTION "public"."cvs_guard_employee_dup"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cvs_guard_employee_dup"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."dm_add_member"("p_thread" "uuid", "p_emp" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."dm_add_member"("p_thread" "uuid", "p_emp" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."dm_add_member"("p_thread" "uuid", "p_emp" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."dm_add_member"("p_thread" "uuid", "p_emp" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."dm_can_chat"("p_other" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."dm_can_chat"("p_other" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."dm_can_chat"("p_other" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."dm_can_chat"("p_other" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."dm_create_group"("p_name" "text", "p_members" "uuid"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."dm_create_group"("p_name" "text", "p_members" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."dm_create_group"("p_name" "text", "p_members" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."dm_create_group"("p_name" "text", "p_members" "uuid"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."dm_is_member"("p_thread" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."dm_is_member"("p_thread" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."dm_is_member"("p_thread" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."dm_is_member"("p_thread" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."dm_join_group"("p_thread" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."dm_join_group"("p_thread" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."dm_join_group"("p_thread" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."dm_join_group"("p_thread" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."dm_leave_group"("p_thread" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."dm_leave_group"("p_thread" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."dm_leave_group"("p_thread" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."dm_leave_group"("p_thread" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."dm_remove_member"("p_thread" "uuid", "p_emp" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."dm_remove_member"("p_thread" "uuid", "p_emp" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."dm_remove_member"("p_thread" "uuid", "p_emp" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."dm_remove_member"("p_thread" "uuid", "p_emp" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."dm_rename_group"("p_thread" "uuid", "p_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."dm_rename_group"("p_thread" "uuid", "p_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."dm_rename_group"("p_thread" "uuid", "p_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."dm_rename_group"("p_thread" "uuid", "p_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."dm_set_translations"("p_msg" "uuid", "p_tr" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."dm_set_translations"("p_msg" "uuid", "p_tr" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."dm_set_translations"("p_msg" "uuid", "p_tr" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."dm_set_translations"("p_msg" "uuid", "p_tr" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."dm_start_thread"("p_other" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."dm_start_thread"("p_other" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."dm_start_thread"("p_other" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."dm_start_thread"("p_other" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."dm_touch_thread"() TO "anon";
GRANT ALL ON FUNCTION "public"."dm_touch_thread"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."dm_touch_thread"() TO "service_role";



GRANT ALL ON FUNCTION "public"."enforce_last_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."enforce_last_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."enforce_last_admin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."gen_public_code"() TO "anon";
GRANT ALL ON FUNCTION "public"."gen_public_code"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."gen_public_code"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_interview_slots"("p_token" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_interview_slots"("p_token" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_interview_slots"("p_token" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_my_client_project_id"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_my_client_project_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_client_project_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_client_project_id"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_my_employee_id"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_my_employee_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_employee_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_employee_id"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_my_employee_project_id"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_my_employee_project_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_employee_project_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_employee_project_id"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_my_project_id"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_my_project_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_project_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_project_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_role_keys"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_role_keys"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_role_keys"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_public_presentation"("p_token" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_public_presentation"("p_token" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_public_presentation"("p_token" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_public_presentation"("p_token" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_showcase"("p_token" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_showcase"("p_token" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_showcase"("p_token" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_showcase"("p_token" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."insight_dispute"("p_id" bigint, "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."insight_dispute"("p_id" bigint, "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."insight_dispute"("p_id" bigint, "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."insight_learning"("p_days" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."insight_learning"("p_days" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."insight_learning"("p_days" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."insight_learning"("p_days" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."insight_mark"("p_id" bigint, "p_state" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."insight_mark"("p_id" bigint, "p_state" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."insight_mark"("p_id" bigint, "p_state" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."insight_mark"("p_id" bigint, "p_state" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."insight_muted_types"("p_days" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."insight_muted_types"("p_days" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."insight_muted_types"("p_days" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."insight_muted_types"("p_days" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."insight_type_key"("p_okey" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."insight_type_key"("p_okey" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."insight_type_key"("p_okey" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."interview_busy_blocks"("p_participants" "uuid"[], "p_from" "date", "p_to" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."interview_busy_blocks"("p_participants" "uuid"[], "p_from" "date", "p_to" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."interview_busy_blocks"("p_participants" "uuid"[], "p_from" "date", "p_to" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_emp_in_my_project"("p_emp" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_emp_in_my_project"("p_emp" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_emp_in_my_project"("p_emp" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_emp_in_my_project"("p_emp" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_finance"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_finance"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_finance"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_finance"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_hr"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_hr"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_hr"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_hr"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_lead_only"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_lead_only"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_lead_only"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_lead_only"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_management"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_management"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_management"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_management"() TO "service_role";
GRANT ALL ON FUNCTION "public"."is_management"() TO "nlquery_ro";



GRANT ALL ON FUNCTION "public"."is_mgmt_call_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_mgmt_call_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_mgmt_call_user"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_planner"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_planner"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_planner"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_planner"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_protected_employee"("emp" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_protected_employee"("emp" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_protected_employee"("emp" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_protected_employee"("emp" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_sales_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_sales_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_sales_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."jobfair_claim"("p_cv_id" "uuid", "p_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."jobfair_claim"("p_cv_id" "uuid", "p_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."jobfair_claim"("p_cv_id" "uuid", "p_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."kb_feedback"("p_query" "uuid", "p_helpful" boolean, "p_note" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."kb_feedback"("p_query" "uuid", "p_helpful" boolean, "p_note" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."kb_feedback"("p_query" "uuid", "p_helpful" boolean, "p_note" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."kb_retrieve"("p_project" "text", "p_q" "text", "p_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."kb_retrieve"("p_project" "text", "p_q" "text", "p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."kb_retrieve"("p_project" "text", "p_q" "text", "p_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."kb_word_hits"("p_q" "text", "p_text" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."kb_word_hits"("p_q" "text", "p_text" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."kb_word_hits"("p_q" "text", "p_text" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."lead_state_persist"() TO "anon";
GRANT ALL ON FUNCTION "public"."lead_state_persist"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."lead_state_persist"() TO "service_role";



GRANT ALL ON FUNCTION "public"."lead_state_restore"() TO "anon";
GRANT ALL ON FUNCTION "public"."lead_state_restore"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."lead_state_restore"() TO "service_role";



GRANT ALL ON FUNCTION "public"."leader_situations"() TO "anon";
GRANT ALL ON FUNCTION "public"."leader_situations"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."leader_situations"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."lena_scan"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."lena_scan"() TO "anon";
GRANT ALL ON FUNCTION "public"."lena_scan"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."lena_scan"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."list_my_showcases"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_my_showcases"() TO "anon";
GRANT ALL ON FUNCTION "public"."list_my_showcases"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."list_my_showcases"() TO "service_role";



GRANT ALL ON FUNCTION "public"."log_client_error"("p" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."log_client_error"("p" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_client_error"("p" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."lookup_pin"("p_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."lookup_pin"("p_code" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."lookup_pin"("p_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lookup_pin"("p_code" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."management_activity_overview"() TO "anon";
GRANT ALL ON FUNCTION "public"."management_activity_overview"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."management_activity_overview"() TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_interview_opened"("p_token" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."mark_interview_opened"("p_token" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_interview_opened"("p_token" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."match_cv_by_email"("p_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."match_cv_by_email"("p_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."match_cv_by_email"("p_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."match_employee_by_email"("p_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."match_employee_by_email"("p_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."match_employee_by_email"("p_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."max_checkin_scan"("p_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."max_checkin_scan"("p_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."max_checkin_scan"("p_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."max_shift_scan"("p_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."max_shift_scan"("p_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."max_shift_scan"("p_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."max_training_scan"("p_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."max_training_scan"("p_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."max_training_scan"("p_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."max_upload_scan"() TO "anon";
GRANT ALL ON FUNCTION "public"."max_upload_scan"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."max_upload_scan"() TO "service_role";



GRANT ALL ON FUNCTION "public"."maya_access_scan"() TO "anon";
GRANT ALL ON FUNCTION "public"."maya_access_scan"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."maya_access_scan"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."maya_system_scan"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."maya_system_scan"() TO "anon";
GRANT ALL ON FUNCTION "public"."maya_system_scan"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."maya_system_scan"() TO "service_role";



GRANT ALL ON FUNCTION "public"."mgmt_task_out_guard"() TO "anon";
GRANT ALL ON FUNCTION "public"."mgmt_task_out_guard"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."mgmt_task_out_guard"() TO "service_role";



GRANT ALL ON FUNCTION "public"."mgmt_task_out_sync"() TO "anon";
GRANT ALL ON FUNCTION "public"."mgmt_task_out_sync"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."mgmt_task_out_sync"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."mn_can_read"("p_project_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mn_can_read"("p_project_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."mn_can_read"("p_project_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mn_can_read"("p_project_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mn_can_write"("p_project_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mn_can_write"("p_project_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."mn_can_write"("p_project_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mn_can_write"("p_project_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mn_employee_on_project"("p_project_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mn_employee_on_project"("p_project_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."mn_employee_on_project"("p_project_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mn_employee_on_project"("p_project_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mn_is_overhead_on_project"("p_project_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mn_is_overhead_on_project"("p_project_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."mn_is_overhead_on_project"("p_project_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mn_is_overhead_on_project"("p_project_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."my_employee_id"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."my_employee_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."my_employee_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."my_employee_id"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."my_permissions"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."my_permissions"() TO "anon";
GRANT ALL ON FUNCTION "public"."my_permissions"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."my_permissions"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."nlquery_exec"("p_sql" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."nlquery_exec"("p_sql" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."nlquery_exec"("p_sql" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."nlquery_exec"("p_sql" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."paul_forecast_scan"("p_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."paul_forecast_scan"("p_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."paul_forecast_scan"("p_date" "date") TO "service_role";



REVOKE ALL ON FUNCTION "public"."paul_whatif"("p_project" "text", "p_min_weeks" integer, "p_min_people" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."paul_whatif"("p_project" "text", "p_min_weeks" integer, "p_min_people" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."paul_whatif"("p_project" "text", "p_min_weeks" integer, "p_min_people" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."paul_whatif"("p_project" "text", "p_min_weeks" integer, "p_min_people" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."perm"("p_uid" "uuid", "p_area" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."perm"("p_uid" "uuid", "p_area" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."perm"("p_uid" "uuid", "p_area" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."perm_allowed_projects"("p_uid" "uuid", "p_area" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."perm_allowed_projects"("p_uid" "uuid", "p_area" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."perm_allowed_projects"("p_uid" "uuid", "p_area" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."perm_area_grant_management"() TO "anon";
GRANT ALL ON FUNCTION "public"."perm_area_grant_management"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."perm_area_grant_management"() TO "service_role";



GRANT ALL ON FUNCTION "public"."perm_area_has_skill"("p_area" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."perm_area_has_skill"("p_area" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."perm_area_has_skill"("p_area" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."perm_caller_emp_id"("p_uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."perm_caller_emp_id"("p_uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."perm_caller_emp_id"("p_uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."perm_caller_rank"("p_uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."perm_caller_rank"("p_uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."perm_caller_rank"("p_uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."perm_caller_skills"("p_uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."perm_caller_skills"("p_uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."perm_caller_skills"("p_uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."perm_emp_row_ok"("p_uid" "uuid", "p_area" "text", "p_emp_id" "uuid", "p_project" "text", "p_skill" "text", "p_position" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."perm_emp_row_ok"("p_uid" "uuid", "p_area" "text", "p_emp_id" "uuid", "p_project" "text", "p_skill" "text", "p_position" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."perm_emp_row_ok"("p_uid" "uuid", "p_area" "text", "p_emp_id" "uuid", "p_project" "text", "p_skill" "text", "p_position" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."perm_mode"("p_uid" "uuid", "p_area" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."perm_mode"("p_uid" "uuid", "p_area" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."perm_mode"("p_uid" "uuid", "p_area" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."perm_overhead_ok"("p_uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."perm_overhead_ok"("p_uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."perm_overhead_ok"("p_uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."perm_proj_ok"("p_uid" "uuid", "p_area" "text", "p_project" "text", "p_skill" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."perm_proj_ok"("p_uid" "uuid", "p_area" "text", "p_project" "text", "p_skill" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."perm_proj_ok"("p_uid" "uuid", "p_area" "text", "p_project" "text", "p_skill" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."perm_salary_ok"("p_uid" "uuid", "p_area" "text", "p_emp_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."perm_salary_ok"("p_uid" "uuid", "p_area" "text", "p_emp_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."perm_salary_ok"("p_uid" "uuid", "p_area" "text", "p_emp_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."permissions_overview"() TO "anon";
GRANT ALL ON FUNCTION "public"."permissions_overview"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."permissions_overview"() TO "service_role";



GRANT ALL ON FUNCTION "public"."promote_employee"("p_payload" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."promote_employee"("p_payload" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."promote_employee"("p_payload" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."protect_salary_on_update"() TO "anon";
GRANT ALL ON FUNCTION "public"."protect_salary_on_update"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."protect_salary_on_update"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."respond_counter"("p_request_id" "uuid", "p_accept" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."respond_counter"("p_request_id" "uuid", "p_accept" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."respond_counter"("p_request_id" "uuid", "p_accept" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."respond_counter"("p_request_id" "uuid", "p_accept" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."sales_can_send"("p_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."sales_can_send"("p_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sales_can_send"("p_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."sales_email_tier"("p_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."sales_email_tier"("p_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sales_email_tier"("p_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."sales_leads_set_tier"() TO "anon";
GRANT ALL ON FUNCTION "public"."sales_leads_set_tier"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sales_leads_set_tier"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sales_mark_dead"() TO "anon";
GRANT ALL ON FUNCTION "public"."sales_mark_dead"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sales_mark_dead"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sales_recompute_scores"() TO "anon";
GRANT ALL ON FUNCTION "public"."sales_recompute_scores"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sales_recompute_scores"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sales_score_for"("p_lead_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."sales_score_for"("p_lead_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sales_score_for"("p_lead_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."session_ping"("p_session_id" "text", "p_view" "text", "p_agent" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."session_ping"("p_session_id" "text", "p_view" "text", "p_agent" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."session_ping"("p_session_id" "text", "p_view" "text", "p_agent" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."session_ping"("p_session_id" "text", "p_view" "text", "p_agent" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_employee_absences"("p_employee_id" "uuid", "p_absences" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."set_employee_absences"("p_employee_id" "uuid", "p_absences" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_employee_absences"("p_employee_id" "uuid", "p_absences" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."spin_wheel"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."spin_wheel"() TO "anon";
GRANT ALL ON FUNCTION "public"."spin_wheel"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."spin_wheel"() TO "service_role";



GRANT ALL ON FUNCTION "public"."staffing_forecast"("p_project" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."staffing_forecast"("p_project" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."staffing_forecast"("p_project" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."staffing_forecast_core"("p_project" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."staffing_forecast_core"("p_project" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."staffing_forecast_core"("p_project" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."staffing_forecast_core"("p_project" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."stamp_by_pin"("p_code" "text", "p_action" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."stamp_by_pin"("p_code" "text", "p_action" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."stamp_by_pin"("p_code" "text", "p_action" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."stamp_by_pin"("p_code" "text", "p_action" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."task_can_substitute"("p_project_id" "text", "p_orig_assignee" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."task_can_substitute"("p_project_id" "text", "p_orig_assignee" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."task_can_substitute"("p_project_id" "text", "p_orig_assignee" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."task_open_counts"() TO "anon";
GRANT ALL ON FUNCTION "public"."task_open_counts"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."task_open_counts"() TO "service_role";



GRANT ALL ON FUNCTION "public"."task_take_over"("p_task_key" "text", "p_project_id" "text", "p_date" "date", "p_orig_assignee" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."task_take_over"("p_task_key" "text", "p_project_id" "text", "p_date" "date", "p_orig_assignee" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."task_take_over"("p_task_key" "text", "p_project_id" "text", "p_date" "date", "p_orig_assignee" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."task_toggle_done"("p_task_key" "text", "p_date" "date", "p_assignee_user" "uuid", "p_project_id" "text", "p_done" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."task_toggle_done"("p_task_key" "text", "p_date" "date", "p_assignee_user" "uuid", "p_project_id" "text", "p_done" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."task_toggle_done"("p_task_key" "text", "p_date" "date", "p_assignee_user" "uuid", "p_project_id" "text", "p_done" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."update_employee_lead"("p_payload" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."update_employee_lead"("p_payload" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_employee_lead"("p_payload" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."usage_day_metrics"("p_from" "date", "p_to" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."usage_day_metrics"("p_from" "date", "p_to" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."usage_day_metrics"("p_from" "date", "p_to" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."usage_day_metrics"("p_from" "date", "p_to" "date") TO "service_role";



REVOKE ALL ON FUNCTION "public"."usage_user_detail"("p_user" "uuid", "p_days" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."usage_user_detail"("p_user" "uuid", "p_days" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."usage_user_detail"("p_user" "uuid", "p_days" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."usage_user_detail"("p_user" "uuid", "p_days" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."vorort_lookup"("p_station" "text", "p_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."vorort_lookup"("p_station" "text", "p_code" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."vorort_lookup"("p_station" "text", "p_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vorort_lookup"("p_station" "text", "p_code" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."vorort_station_ok"("p_station" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."vorort_station_ok"("p_station" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vorort_station_ok"("p_station" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."vorort_submit"("p_station" "text", "p_code" "text", "p_data" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."vorort_submit"("p_station" "text", "p_code" "text", "p_data" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."vorort_submit"("p_station" "text", "p_code" "text", "p_data" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vorort_submit"("p_station" "text", "p_code" "text", "p_data" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."windsor_leads_auto_discard"() TO "anon";
GRANT ALL ON FUNCTION "public"."windsor_leads_auto_discard"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."windsor_leads_auto_discard"() TO "service_role";



GRANT ALL ON FUNCTION "public"."windsor_marketing_dedup"() TO "anon";
GRANT ALL ON FUNCTION "public"."windsor_marketing_dedup"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."windsor_marketing_dedup"() TO "service_role";



GRANT ALL ON FUNCTION "public"."windsor_marketing_merge"() TO "anon";
GRANT ALL ON FUNCTION "public"."windsor_marketing_merge"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."windsor_marketing_merge"() TO "service_role";



GRANT ALL ON TABLE "public"."call_criteria" TO "anon";
GRANT ALL ON TABLE "public"."call_criteria" TO "authenticated";
GRANT ALL ON TABLE "public"."call_criteria" TO "service_role";
GRANT SELECT ON TABLE "public"."call_criteria" TO "agent_ro";



GRANT ALL ON TABLE "public"."call_samples" TO "anon";
GRANT ALL ON TABLE "public"."call_samples" TO "authenticated";
GRANT ALL ON TABLE "public"."call_samples" TO "service_role";
GRANT SELECT ON TABLE "public"."call_samples" TO "agent_ro";



GRANT ALL ON TABLE "public"."call_scores" TO "anon";
GRANT ALL ON TABLE "public"."call_scores" TO "authenticated";
GRANT ALL ON TABLE "public"."call_scores" TO "service_role";
GRANT SELECT ON TABLE "public"."call_scores" TO "agent_ro";



GRANT ALL ON TABLE "public"."app_users" TO "anon";
GRANT ALL ON TABLE "public"."app_users" TO "authenticated";
GRANT ALL ON TABLE "public"."app_users" TO "service_role";
GRANT SELECT ON TABLE "public"."app_users" TO "agent_ro";



GRANT ALL ON TABLE "public"."daily_hours" TO "anon";
GRANT ALL ON TABLE "public"."daily_hours" TO "authenticated";
GRANT ALL ON TABLE "public"."daily_hours" TO "service_role";
GRANT SELECT ON TABLE "public"."daily_hours" TO "agent_ro";



GRANT ALL ON TABLE "public"."kpi_config" TO "anon";
GRANT ALL ON TABLE "public"."kpi_config" TO "authenticated";
GRANT ALL ON TABLE "public"."kpi_config" TO "service_role";
GRANT SELECT ON TABLE "public"."kpi_config" TO "agent_ro";



GRANT ALL ON TABLE "public"."kpi_entries" TO "anon";
GRANT ALL ON TABLE "public"."kpi_entries" TO "authenticated";
GRANT ALL ON TABLE "public"."kpi_entries" TO "service_role";
GRANT SELECT ON TABLE "public"."kpi_entries" TO "agent_ro";



GRANT ALL ON TABLE "public"."kpi_project_entries" TO "anon";
GRANT ALL ON TABLE "public"."kpi_project_entries" TO "authenticated";
GRANT ALL ON TABLE "public"."kpi_project_entries" TO "service_role";
GRANT SELECT ON TABLE "public"."kpi_project_entries" TO "agent_ro";



GRANT ALL ON TABLE "public"."projects" TO "anon";
GRANT ALL ON TABLE "public"."projects" TO "authenticated";
GRANT ALL ON TABLE "public"."projects" TO "service_role";
GRANT SELECT ON TABLE "public"."projects" TO "agent_ro";



GRANT ALL ON TABLE "public"."report_forecast" TO "anon";
GRANT ALL ON TABLE "public"."report_forecast" TO "authenticated";
GRANT ALL ON TABLE "public"."report_forecast" TO "service_role";
GRANT SELECT ON TABLE "public"."report_forecast" TO "agent_ro";



GRANT ALL ON TABLE "public"."report_fte" TO "anon";
GRANT ALL ON TABLE "public"."report_fte" TO "authenticated";
GRANT ALL ON TABLE "public"."report_fte" TO "service_role";
GRANT SELECT ON TABLE "public"."report_fte" TO "agent_ro";



GRANT ALL ON TABLE "public"."report_longterm" TO "anon";
GRANT ALL ON TABLE "public"."report_longterm" TO "authenticated";
GRANT ALL ON TABLE "public"."report_longterm" TO "service_role";
GRANT SELECT ON TABLE "public"."report_longterm" TO "agent_ro";



GRANT ALL ON TABLE "public"."report_measures" TO "anon";
GRANT ALL ON TABLE "public"."report_measures" TO "authenticated";
GRANT ALL ON TABLE "public"."report_measures" TO "service_role";
GRANT SELECT ON TABLE "public"."report_measures" TO "agent_ro";



GRANT ALL ON TABLE "public"."shift_assignments" TO "anon";
GRANT ALL ON TABLE "public"."shift_assignments" TO "authenticated";
GRANT ALL ON TABLE "public"."shift_assignments" TO "service_role";
GRANT SELECT ON TABLE "public"."shift_assignments" TO "agent_ro";



GRANT ALL ON TABLE "public"."weekly_calls" TO "anon";
GRANT ALL ON TABLE "public"."weekly_calls" TO "authenticated";
GRANT ALL ON TABLE "public"."weekly_calls" TO "service_role";
GRANT SELECT ON TABLE "public"."weekly_calls" TO "agent_ro";



GRANT ALL ON TABLE "public"."weekly_gauges" TO "anon";
GRANT ALL ON TABLE "public"."weekly_gauges" TO "authenticated";
GRANT ALL ON TABLE "public"."weekly_gauges" TO "service_role";
GRANT SELECT ON TABLE "public"."weekly_gauges" TO "agent_ro";



GRANT ALL ON TABLE "public"."data_imports" TO "anon";
GRANT ALL ON TABLE "public"."data_imports" TO "authenticated";
GRANT ALL ON TABLE "public"."data_imports" TO "service_role";
GRANT SELECT ON TABLE "public"."data_imports" TO "agent_ro";



GRANT ALL ON TABLE "public"."weekly_hours_legacy" TO "anon";
GRANT ALL ON TABLE "public"."weekly_hours_legacy" TO "authenticated";
GRANT ALL ON TABLE "public"."weekly_hours_legacy" TO "service_role";
GRANT SELECT ON TABLE "public"."weekly_hours_legacy" TO "agent_ro";



GRANT ALL ON TABLE "public"."weekly_hours" TO "anon";
GRANT ALL ON TABLE "public"."weekly_hours" TO "authenticated";
GRANT ALL ON TABLE "public"."weekly_hours" TO "service_role";
GRANT SELECT ON TABLE "public"."weekly_hours" TO "agent_ro";



GRANT ALL ON TABLE "public"."windsor_marketing" TO "anon";
GRANT ALL ON TABLE "public"."windsor_marketing" TO "authenticated";
GRANT ALL ON TABLE "public"."windsor_marketing" TO "service_role";
GRANT SELECT ON TABLE "public"."windsor_marketing" TO "agent_ro";



GRANT ALL ON TABLE "public"."activity_log" TO "anon";
GRANT ALL ON TABLE "public"."activity_log" TO "authenticated";
GRANT ALL ON TABLE "public"."activity_log" TO "service_role";
GRANT SELECT ON TABLE "public"."activity_log" TO "agent_ro";



GRANT ALL ON TABLE "public"."agent_action_log" TO "anon";
GRANT ALL ON TABLE "public"."agent_action_log" TO "authenticated";
GRANT ALL ON TABLE "public"."agent_action_log" TO "service_role";



GRANT ALL ON TABLE "public"."agent_actions" TO "anon";
GRANT ALL ON TABLE "public"."agent_actions" TO "authenticated";
GRANT ALL ON TABLE "public"."agent_actions" TO "service_role";



GRANT ALL ON TABLE "public"."agent_checks" TO "anon";
GRANT ALL ON TABLE "public"."agent_checks" TO "authenticated";
GRANT ALL ON TABLE "public"."agent_checks" TO "service_role";
GRANT SELECT ON TABLE "public"."agent_checks" TO "agent_ro";



GRANT ALL ON TABLE "public"."agent_conversations" TO "anon";
GRANT ALL ON TABLE "public"."agent_conversations" TO "authenticated";
GRANT ALL ON TABLE "public"."agent_conversations" TO "service_role";



GRANT ALL ON SEQUENCE "public"."agent_conversations_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."agent_conversations_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."agent_conversations_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."agent_digests" TO "anon";
GRANT ALL ON TABLE "public"."agent_digests" TO "authenticated";
GRANT ALL ON TABLE "public"."agent_digests" TO "service_role";



GRANT ALL ON TABLE "public"."agent_escalations" TO "anon";
GRANT ALL ON TABLE "public"."agent_escalations" TO "authenticated";
GRANT ALL ON TABLE "public"."agent_escalations" TO "service_role";



GRANT ALL ON SEQUENCE "public"."agent_escalations_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."agent_escalations_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."agent_escalations_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."agent_handoffs" TO "anon";
GRANT ALL ON TABLE "public"."agent_handoffs" TO "authenticated";
GRANT ALL ON TABLE "public"."agent_handoffs" TO "service_role";



GRANT ALL ON TABLE "public"."agent_insights" TO "anon";
GRANT ALL ON TABLE "public"."agent_insights" TO "authenticated";
GRANT ALL ON TABLE "public"."agent_insights" TO "service_role";



GRANT ALL ON SEQUENCE "public"."agent_insights_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."agent_insights_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."agent_insights_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."agent_observations" TO "anon";
GRANT ALL ON TABLE "public"."agent_observations" TO "authenticated";
GRANT ALL ON TABLE "public"."agent_observations" TO "service_role";
GRANT SELECT ON TABLE "public"."agent_observations" TO "agent_ro";



GRANT ALL ON SEQUENCE "public"."agent_observations_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."agent_observations_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."agent_observations_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."agent_prefs" TO "anon";
GRANT ALL ON TABLE "public"."agent_prefs" TO "authenticated";
GRANT ALL ON TABLE "public"."agent_prefs" TO "service_role";



GRANT ALL ON TABLE "public"."ai_access_prefs" TO "anon";
GRANT ALL ON TABLE "public"."ai_access_prefs" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_access_prefs" TO "service_role";



GRANT ALL ON TABLE "public"."ai_agents" TO "anon";
GRANT ALL ON TABLE "public"."ai_agents" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_agents" TO "service_role";



GRANT ALL ON TABLE "public"."app_config" TO "anon";
GRANT ALL ON TABLE "public"."app_config" TO "authenticated";
GRANT ALL ON TABLE "public"."app_config" TO "service_role";
GRANT SELECT ON TABLE "public"."app_config" TO "agent_ro";



GRANT ALL ON TABLE "public"."applicant_messages" TO "anon";
GRANT ALL ON TABLE "public"."applicant_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."applicant_messages" TO "service_role";



GRANT ALL ON TABLE "public"."assistant_gaps" TO "anon";
GRANT ALL ON TABLE "public"."assistant_gaps" TO "authenticated";
GRANT ALL ON TABLE "public"."assistant_gaps" TO "service_role";
GRANT SELECT ON TABLE "public"."assistant_gaps" TO "agent_ro";



GRANT ALL ON TABLE "public"."calendar_events" TO "anon";
GRANT ALL ON TABLE "public"."calendar_events" TO "authenticated";
GRANT ALL ON TABLE "public"."calendar_events" TO "service_role";



GRANT ALL ON TABLE "public"."calendar_overrides" TO "anon";
GRANT ALL ON TABLE "public"."calendar_overrides" TO "authenticated";
GRANT ALL ON TABLE "public"."calendar_overrides" TO "service_role";



GRANT ALL ON TABLE "public"."call_score_config" TO "anon";
GRANT ALL ON TABLE "public"."call_score_config" TO "authenticated";
GRANT ALL ON TABLE "public"."call_score_config" TO "service_role";



GRANT ALL ON TABLE "public"."chat_flags" TO "anon";
GRANT ALL ON TABLE "public"."chat_flags" TO "authenticated";
GRANT ALL ON TABLE "public"."chat_flags" TO "service_role";



GRANT ALL ON TABLE "public"."chat_universal_contacts" TO "anon";
GRANT ALL ON TABLE "public"."chat_universal_contacts" TO "authenticated";
GRANT ALL ON TABLE "public"."chat_universal_contacts" TO "service_role";



GRANT ALL ON TABLE "public"."clara_handovers" TO "anon";
GRANT ALL ON TABLE "public"."clara_handovers" TO "authenticated";
GRANT ALL ON TABLE "public"."clara_handovers" TO "service_role";



GRANT ALL ON TABLE "public"."clara_rejections" TO "anon";
GRANT ALL ON TABLE "public"."clara_rejections" TO "authenticated";
GRANT ALL ON TABLE "public"."clara_rejections" TO "service_role";



GRANT ALL ON TABLE "public"."client_accounts" TO "anon";
GRANT ALL ON TABLE "public"."client_accounts" TO "authenticated";
GRANT ALL ON TABLE "public"."client_accounts" TO "service_role";



GRANT ALL ON TABLE "public"."client_call_scores" TO "authenticated";
GRANT ALL ON TABLE "public"."client_call_scores" TO "service_role";



GRANT ALL ON TABLE "public"."client_errors" TO "anon";
GRANT ALL ON TABLE "public"."client_errors" TO "authenticated";
GRANT ALL ON TABLE "public"."client_errors" TO "service_role";



GRANT ALL ON TABLE "public"."client_meeting_briefs" TO "anon";
GRANT ALL ON TABLE "public"."client_meeting_briefs" TO "authenticated";
GRANT ALL ON TABLE "public"."client_meeting_briefs" TO "service_role";



GRANT ALL ON TABLE "public"."contract_templates" TO "anon";
GRANT ALL ON TABLE "public"."contract_templates" TO "authenticated";
GRANT ALL ON TABLE "public"."contract_templates" TO "service_role";



GRANT ALL ON TABLE "public"."cv_enrich_forms" TO "anon";
GRANT ALL ON TABLE "public"."cv_enrich_forms" TO "authenticated";
GRANT ALL ON TABLE "public"."cv_enrich_forms" TO "service_role";



GRANT ALL ON TABLE "public"."cv_enrich_invites" TO "anon";
GRANT ALL ON TABLE "public"."cv_enrich_invites" TO "authenticated";
GRANT ALL ON TABLE "public"."cv_enrich_invites" TO "service_role";



GRANT ALL ON TABLE "public"."daily_mailer" TO "anon";
GRANT ALL ON TABLE "public"."daily_mailer" TO "authenticated";
GRANT ALL ON TABLE "public"."daily_mailer" TO "service_role";
GRANT SELECT ON TABLE "public"."daily_mailer" TO "agent_ro";



GRANT ALL ON TABLE "public"."daily_report_summaries" TO "anon";
GRANT ALL ON TABLE "public"."daily_report_summaries" TO "authenticated";
GRANT ALL ON TABLE "public"."daily_report_summaries" TO "service_role";



GRANT ALL ON TABLE "public"."daily_reports" TO "anon";
GRANT ALL ON TABLE "public"."daily_reports" TO "authenticated";
GRANT ALL ON TABLE "public"."daily_reports" TO "service_role";



GRANT ALL ON TABLE "public"."daily_tasks_done" TO "anon";
GRANT ALL ON TABLE "public"."daily_tasks_done" TO "authenticated";
GRANT ALL ON TABLE "public"."daily_tasks_done" TO "service_role";



GRANT ALL ON TABLE "public"."dm_messages" TO "anon";
GRANT ALL ON TABLE "public"."dm_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."dm_messages" TO "service_role";



GRANT ALL ON TABLE "public"."dm_participants" TO "anon";
GRANT ALL ON TABLE "public"."dm_participants" TO "authenticated";
GRANT ALL ON TABLE "public"."dm_participants" TO "service_role";



GRANT ALL ON TABLE "public"."dm_reads" TO "anon";
GRANT ALL ON TABLE "public"."dm_reads" TO "authenticated";
GRANT ALL ON TABLE "public"."dm_reads" TO "service_role";



GRANT ALL ON TABLE "public"."dm_threads" TO "anon";
GRANT ALL ON TABLE "public"."dm_threads" TO "authenticated";
GRANT ALL ON TABLE "public"."dm_threads" TO "service_role";



GRANT ALL ON TABLE "public"."employee_contracts" TO "anon";
GRANT ALL ON TABLE "public"."employee_contracts" TO "authenticated";
GRANT ALL ON TABLE "public"."employee_contracts" TO "service_role";



GRANT ALL ON TABLE "public"."employee_documents" TO "anon";
GRANT ALL ON TABLE "public"."employee_documents" TO "authenticated";
GRANT ALL ON TABLE "public"."employee_documents" TO "service_role";



GRANT ALL ON TABLE "public"."employees_client_view" TO "anon";
GRANT ALL ON TABLE "public"."employees_client_view" TO "authenticated";
GRANT ALL ON TABLE "public"."employees_client_view" TO "service_role";



GRANT ALL ON TABLE "public"."employees_masked" TO "anon";
GRANT ALL ON TABLE "public"."employees_masked" TO "authenticated";
GRANT ALL ON TABLE "public"."employees_masked" TO "service_role";



GRANT ALL ON TABLE "public"."employees_masked_lite" TO "anon";
GRANT ALL ON TABLE "public"."employees_masked_lite" TO "authenticated";
GRANT ALL ON TABLE "public"."employees_masked_lite" TO "service_role";



GRANT ALL ON TABLE "public"."employees_self" TO "anon";
GRANT ALL ON TABLE "public"."employees_self" TO "authenticated";
GRANT ALL ON TABLE "public"."employees_self" TO "service_role";



GRANT ALL ON TABLE "public"."employees_team_view" TO "anon";
GRANT ALL ON TABLE "public"."employees_team_view" TO "authenticated";
GRANT ALL ON TABLE "public"."employees_team_view" TO "service_role";



GRANT ALL ON TABLE "public"."feedback_answers" TO "anon";
GRANT ALL ON TABLE "public"."feedback_answers" TO "authenticated";
GRANT ALL ON TABLE "public"."feedback_answers" TO "service_role";



GRANT ALL ON TABLE "public"."feedback_questions" TO "anon";
GRANT ALL ON TABLE "public"."feedback_questions" TO "authenticated";
GRANT ALL ON TABLE "public"."feedback_questions" TO "service_role";



GRANT ALL ON TABLE "public"."feedback_sessions" TO "anon";
GRANT ALL ON TABLE "public"."feedback_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."feedback_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."forecast_actuals" TO "anon";
GRANT ALL ON TABLE "public"."forecast_actuals" TO "authenticated";
GRANT ALL ON TABLE "public"."forecast_actuals" TO "service_role";



GRANT ALL ON TABLE "public"."forecast_config" TO "anon";
GRANT ALL ON TABLE "public"."forecast_config" TO "authenticated";
GRANT ALL ON TABLE "public"."forecast_config" TO "service_role";



GRANT ALL ON TABLE "public"."forecast_demand" TO "anon";
GRANT ALL ON TABLE "public"."forecast_demand" TO "authenticated";
GRANT ALL ON TABLE "public"."forecast_demand" TO "service_role";



GRANT ALL ON TABLE "public"."import_aliases" TO "anon";
GRANT ALL ON TABLE "public"."import_aliases" TO "authenticated";
GRANT ALL ON TABLE "public"."import_aliases" TO "service_role";



GRANT ALL ON TABLE "public"."interview_invites" TO "anon";
GRANT ALL ON TABLE "public"."interview_invites" TO "authenticated";
GRANT ALL ON TABLE "public"."interview_invites" TO "service_role";



GRANT ALL ON TABLE "public"."kb_chunks" TO "anon";
GRANT ALL ON TABLE "public"."kb_chunks" TO "authenticated";
GRANT ALL ON TABLE "public"."kb_chunks" TO "service_role";



GRANT ALL ON TABLE "public"."kb_documents" TO "anon";
GRANT ALL ON TABLE "public"."kb_documents" TO "authenticated";
GRANT ALL ON TABLE "public"."kb_documents" TO "service_role";



GRANT ALL ON TABLE "public"."kb_facts" TO "anon";
GRANT ALL ON TABLE "public"."kb_facts" TO "authenticated";
GRANT ALL ON TABLE "public"."kb_facts" TO "service_role";



GRANT ALL ON TABLE "public"."kb_queries" TO "anon";
GRANT ALL ON TABLE "public"."kb_queries" TO "authenticated";
GRANT ALL ON TABLE "public"."kb_queries" TO "service_role";



GRANT ALL ON TABLE "public"."kb_regions" TO "anon";
GRANT ALL ON TABLE "public"."kb_regions" TO "authenticated";
GRANT ALL ON TABLE "public"."kb_regions" TO "service_role";



GRANT ALL ON TABLE "public"."lead_import_state" TO "anon";
GRANT ALL ON TABLE "public"."lead_import_state" TO "authenticated";
GRANT ALL ON TABLE "public"."lead_import_state" TO "service_role";



GRANT ALL ON TABLE "public"."leader_nudge_prompts" TO "anon";
GRANT ALL ON TABLE "public"."leader_nudge_prompts" TO "authenticated";
GRANT ALL ON TABLE "public"."leader_nudge_prompts" TO "service_role";



GRANT ALL ON TABLE "public"."location_monthly" TO "anon";
GRANT ALL ON TABLE "public"."location_monthly" TO "authenticated";
GRANT ALL ON TABLE "public"."location_monthly" TO "service_role";



GRANT ALL ON TABLE "public"."locations" TO "anon";
GRANT ALL ON TABLE "public"."locations" TO "authenticated";
GRANT ALL ON TABLE "public"."locations" TO "service_role";



GRANT ALL ON TABLE "public"."mail_attachments" TO "anon";
GRANT ALL ON TABLE "public"."mail_attachments" TO "authenticated";
GRANT ALL ON TABLE "public"."mail_attachments" TO "service_role";



GRANT ALL ON TABLE "public"."mail_conversation_meta" TO "anon";
GRANT ALL ON TABLE "public"."mail_conversation_meta" TO "authenticated";
GRANT ALL ON TABLE "public"."mail_conversation_meta" TO "service_role";



GRANT ALL ON TABLE "public"."mail_folders" TO "anon";
GRANT ALL ON TABLE "public"."mail_folders" TO "authenticated";
GRANT ALL ON TABLE "public"."mail_folders" TO "service_role";



GRANT ALL ON TABLE "public"."mail_messages" TO "anon";
GRANT ALL ON TABLE "public"."mail_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."mail_messages" TO "service_role";



GRANT ALL ON TABLE "public"."mail_senders" TO "anon";
GRANT ALL ON TABLE "public"."mail_senders" TO "authenticated";
GRANT ALL ON TABLE "public"."mail_senders" TO "service_role";



GRANT ALL ON TABLE "public"."mail_tags" TO "anon";
GRANT ALL ON TABLE "public"."mail_tags" TO "authenticated";
GRANT ALL ON TABLE "public"."mail_tags" TO "service_role";



GRANT ALL ON TABLE "public"."mail_templates" TO "anon";
GRANT ALL ON TABLE "public"."mail_templates" TO "authenticated";
GRANT ALL ON TABLE "public"."mail_templates" TO "service_role";



GRANT ALL ON TABLE "public"."meeting_note_comments" TO "anon";
GRANT ALL ON TABLE "public"."meeting_note_comments" TO "authenticated";
GRANT ALL ON TABLE "public"."meeting_note_comments" TO "service_role";



GRANT ALL ON TABLE "public"."meeting_note_items" TO "anon";
GRANT ALL ON TABLE "public"."meeting_note_items" TO "authenticated";
GRANT ALL ON TABLE "public"."meeting_note_items" TO "service_role";



GRANT ALL ON TABLE "public"."meeting_notes" TO "anon";
GRANT ALL ON TABLE "public"."meeting_notes" TO "authenticated";
GRANT ALL ON TABLE "public"."meeting_notes" TO "service_role";



GRANT ALL ON TABLE "public"."mgmt_call_access" TO "anon";
GRANT ALL ON TABLE "public"."mgmt_call_access" TO "authenticated";
GRANT ALL ON TABLE "public"."mgmt_call_access" TO "service_role";



GRANT ALL ON TABLE "public"."mgmt_call_items" TO "anon";
GRANT ALL ON TABLE "public"."mgmt_call_items" TO "authenticated";
GRANT ALL ON TABLE "public"."mgmt_call_items" TO "service_role";



GRANT ALL ON TABLE "public"."mgmt_calls" TO "anon";
GRANT ALL ON TABLE "public"."mgmt_calls" TO "authenticated";
GRANT ALL ON TABLE "public"."mgmt_calls" TO "service_role";



GRANT ALL ON TABLE "public"."mgmt_task_out" TO "anon";
GRANT ALL ON TABLE "public"."mgmt_task_out" TO "authenticated";
GRANT ALL ON TABLE "public"."mgmt_task_out" TO "service_role";



GRANT ALL ON TABLE "public"."notify_prefs" TO "anon";
GRANT ALL ON TABLE "public"."notify_prefs" TO "authenticated";
GRANT ALL ON TABLE "public"."notify_prefs" TO "service_role";



GRANT ALL ON TABLE "public"."org_nodes" TO "anon";
GRANT ALL ON TABLE "public"."org_nodes" TO "authenticated";
GRANT ALL ON TABLE "public"."org_nodes" TO "service_role";



GRANT ALL ON TABLE "public"."partner_agents" TO "anon";
GRANT ALL ON TABLE "public"."partner_agents" TO "authenticated";
GRANT ALL ON TABLE "public"."partner_agents" TO "service_role";



GRANT ALL ON TABLE "public"."payroll_inputs" TO "anon";
GRANT ALL ON TABLE "public"."payroll_inputs" TO "authenticated";
GRANT ALL ON TABLE "public"."payroll_inputs" TO "service_role";



GRANT ALL ON TABLE "public"."payslips" TO "anon";
GRANT ALL ON TABLE "public"."payslips" TO "authenticated";
GRANT ALL ON TABLE "public"."payslips" TO "service_role";



GRANT ALL ON TABLE "public"."permission_areas" TO "anon";
GRANT ALL ON TABLE "public"."permission_areas" TO "authenticated";
GRANT ALL ON TABLE "public"."permission_areas" TO "service_role";



GRANT ALL ON TABLE "public"."position_config_client_view" TO "anon";
GRANT ALL ON TABLE "public"."position_config_client_view" TO "authenticated";
GRANT ALL ON TABLE "public"."position_config_client_view" TO "service_role";



GRANT ALL ON TABLE "public"."presentation_comments" TO "anon";
GRANT ALL ON TABLE "public"."presentation_comments" TO "authenticated";
GRANT ALL ON TABLE "public"."presentation_comments" TO "service_role";



GRANT ALL ON TABLE "public"."presentation_templates" TO "anon";
GRANT ALL ON TABLE "public"."presentation_templates" TO "authenticated";
GRANT ALL ON TABLE "public"."presentation_templates" TO "service_role";



GRANT ALL ON TABLE "public"."presentations" TO "anon";
GRANT ALL ON TABLE "public"."presentations" TO "authenticated";
GRANT ALL ON TABLE "public"."presentations" TO "service_role";



GRANT ALL ON TABLE "public"."project_skill_profiles" TO "anon";
GRANT ALL ON TABLE "public"."project_skill_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."project_skill_profiles" TO "service_role";



GRANT ALL ON TABLE "public"."project_skills" TO "anon";
GRANT ALL ON TABLE "public"."project_skills" TO "authenticated";
GRANT ALL ON TABLE "public"."project_skills" TO "service_role";



GRANT ALL ON TABLE "public"."project_trainings" TO "anon";
GRANT ALL ON TABLE "public"."project_trainings" TO "authenticated";
GRANT ALL ON TABLE "public"."project_trainings" TO "service_role";



GRANT ALL ON TABLE "public"."reminder_schedule" TO "anon";
GRANT ALL ON TABLE "public"."reminder_schedule" TO "authenticated";
GRANT ALL ON TABLE "public"."reminder_schedule" TO "service_role";



GRANT ALL ON TABLE "public"."rk_monthly" TO "anon";
GRANT ALL ON TABLE "public"."rk_monthly" TO "authenticated";
GRANT ALL ON TABLE "public"."rk_monthly" TO "service_role";



GRANT ALL ON TABLE "public"."rk_overhead" TO "anon";
GRANT ALL ON TABLE "public"."rk_overhead" TO "authenticated";
GRANT ALL ON TABLE "public"."rk_overhead" TO "service_role";



GRANT ALL ON TABLE "public"."role_permissions" TO "anon";
GRANT ALL ON TABLE "public"."role_permissions" TO "authenticated";
GRANT ALL ON TABLE "public"."role_permissions" TO "service_role";



GRANT ALL ON TABLE "public"."roles_definitions" TO "anon";
GRANT ALL ON TABLE "public"."roles_definitions" TO "authenticated";
GRANT ALL ON TABLE "public"."roles_definitions" TO "service_role";



GRANT ALL ON TABLE "public"."sales_access" TO "anon";
GRANT ALL ON TABLE "public"."sales_access" TO "authenticated";
GRANT ALL ON TABLE "public"."sales_access" TO "service_role";



GRANT ALL ON TABLE "public"."sales_events" TO "anon";
GRANT ALL ON TABLE "public"."sales_events" TO "authenticated";
GRANT ALL ON TABLE "public"."sales_events" TO "service_role";



GRANT ALL ON TABLE "public"."sales_leads" TO "anon";
GRANT ALL ON TABLE "public"."sales_leads" TO "authenticated";
GRANT ALL ON TABLE "public"."sales_leads" TO "service_role";



GRANT ALL ON TABLE "public"."sales_suppression" TO "anon";
GRANT ALL ON TABLE "public"."sales_suppression" TO "authenticated";
GRANT ALL ON TABLE "public"."sales_suppression" TO "service_role";



GRANT ALL ON TABLE "public"."sales_templates" TO "anon";
GRANT ALL ON TABLE "public"."sales_templates" TO "authenticated";
GRANT ALL ON TABLE "public"."sales_templates" TO "service_role";



GRANT ALL ON TABLE "public"."sales_upload_maps" TO "anon";
GRANT ALL ON TABLE "public"."sales_upload_maps" TO "authenticated";
GRANT ALL ON TABLE "public"."sales_upload_maps" TO "service_role";



GRANT ALL ON TABLE "public"."shift_checkins" TO "anon";
GRANT ALL ON TABLE "public"."shift_checkins" TO "authenticated";
GRANT ALL ON TABLE "public"."shift_checkins" TO "service_role";



GRANT ALL ON TABLE "public"."shifts_client_view" TO "anon";
GRANT ALL ON TABLE "public"."shifts_client_view" TO "authenticated";
GRANT ALL ON TABLE "public"."shifts_client_view" TO "service_role";



GRANT ALL ON TABLE "public"."showcases" TO "anon";
GRANT ALL ON TABLE "public"."showcases" TO "authenticated";
GRANT ALL ON TABLE "public"."showcases" TO "service_role";



GRANT ALL ON TABLE "public"."spaces" TO "anon";
GRANT ALL ON TABLE "public"."spaces" TO "authenticated";
GRANT ALL ON TABLE "public"."spaces" TO "service_role";



GRANT ALL ON TABLE "public"."system_findings" TO "anon";
GRANT ALL ON TABLE "public"."system_findings" TO "authenticated";
GRANT ALL ON TABLE "public"."system_findings" TO "service_role";



GRANT ALL ON TABLE "public"."task_assignments" TO "anon";
GRANT ALL ON TABLE "public"."task_assignments" TO "authenticated";
GRANT ALL ON TABLE "public"."task_assignments" TO "service_role";



GRANT ALL ON TABLE "public"."task_catalog" TO "anon";
GRANT ALL ON TABLE "public"."task_catalog" TO "authenticated";
GRANT ALL ON TABLE "public"."task_catalog" TO "service_role";



GRANT ALL ON TABLE "public"."task_snooze" TO "anon";
GRANT ALL ON TABLE "public"."task_snooze" TO "authenticated";
GRANT ALL ON TABLE "public"."task_snooze" TO "service_role";



GRANT ALL ON TABLE "public"."task_takeover" TO "anon";
GRANT ALL ON TABLE "public"."task_takeover" TO "authenticated";
GRANT ALL ON TABLE "public"."task_takeover" TO "service_role";



GRANT ALL ON TABLE "public"."time_pin_attempts" TO "anon";
GRANT ALL ON TABLE "public"."time_pin_attempts" TO "authenticated";
GRANT ALL ON TABLE "public"."time_pin_attempts" TO "service_role";



GRANT ALL ON TABLE "public"."time_pins" TO "anon";
GRANT ALL ON TABLE "public"."time_pins" TO "authenticated";
GRANT ALL ON TABLE "public"."time_pins" TO "service_role";



GRANT ALL ON TABLE "public"."time_sessions" TO "anon";
GRANT ALL ON TABLE "public"."time_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."time_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."training_plans" TO "anon";
GRANT ALL ON TABLE "public"."training_plans" TO "authenticated";
GRANT ALL ON TABLE "public"."training_plans" TO "service_role";



GRANT ALL ON TABLE "public"."upload_project_owner" TO "anon";
GRANT ALL ON TABLE "public"."upload_project_owner" TO "authenticated";
GRANT ALL ON TABLE "public"."upload_project_owner" TO "service_role";



GRANT ALL ON TABLE "public"."upload_schedule" TO "anon";
GRANT ALL ON TABLE "public"."upload_schedule" TO "authenticated";
GRANT ALL ON TABLE "public"."upload_schedule" TO "service_role";



GRANT ALL ON TABLE "public"."usage_digests" TO "anon";
GRANT ALL ON TABLE "public"."usage_digests" TO "authenticated";
GRANT ALL ON TABLE "public"."usage_digests" TO "service_role";



GRANT ALL ON TABLE "public"."user_permissions" TO "anon";
GRANT ALL ON TABLE "public"."user_permissions" TO "authenticated";
GRANT ALL ON TABLE "public"."user_permissions" TO "service_role";



GRANT ALL ON TABLE "public"."user_prefs" TO "anon";
GRANT ALL ON TABLE "public"."user_prefs" TO "authenticated";
GRANT ALL ON TABLE "public"."user_prefs" TO "service_role";



GRANT ALL ON TABLE "public"."user_sessions" TO "anon";
GRANT ALL ON TABLE "public"."user_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."user_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."vacation_accounts" TO "anon";
GRANT ALL ON TABLE "public"."vacation_accounts" TO "authenticated";
GRANT ALL ON TABLE "public"."vacation_accounts" TO "service_role";



GRANT ALL ON TABLE "public"."vacation_requests" TO "anon";
GRANT ALL ON TABLE "public"."vacation_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."vacation_requests" TO "service_role";



GRANT ALL ON TABLE "public"."vorort_attempts" TO "anon";
GRANT ALL ON TABLE "public"."vorort_attempts" TO "authenticated";
GRANT ALL ON TABLE "public"."vorort_attempts" TO "service_role";



GRANT ALL ON SEQUENCE "public"."vorort_attempts_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."vorort_attempts_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."vorort_attempts_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."wheel_budgets" TO "anon";
GRANT ALL ON TABLE "public"."wheel_budgets" TO "authenticated";
GRANT ALL ON TABLE "public"."wheel_budgets" TO "service_role";



GRANT ALL ON TABLE "public"."wheel_specials" TO "anon";
GRANT ALL ON TABLE "public"."wheel_specials" TO "authenticated";
GRANT ALL ON TABLE "public"."wheel_specials" TO "service_role";



GRANT ALL ON TABLE "public"."wheel_spins" TO "anon";
GRANT ALL ON TABLE "public"."wheel_spins" TO "authenticated";
GRANT ALL ON TABLE "public"."wheel_spins" TO "service_role";



GRANT ALL ON TABLE "public"."windsor_leads" TO "anon";
GRANT ALL ON TABLE "public"."windsor_leads" TO "authenticated";
GRANT ALL ON TABLE "public"."windsor_leads" TO "service_role";
GRANT SELECT ON TABLE "public"."windsor_leads" TO "agent_ro";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







