-- Rechte Schnitt 4: geteilte DB-Prädikate, verallgemeinert aus den ai_*-Helfern, aber JE BEREICH und aus dem
-- neuen Modell (perm(uid,area)). NOCH KEINE Policy/Ansicht nutzt sie — reine Bausteine für Schnitt 5 (KI) und
-- Schnitt 6 (App-RLS). Additiv, keine Durchsetzung, geringes Risiko. uid-Default = auth.uid().
-- Achsen aus perm(): visible, mode(none/read/edit), salary(none/own/all), direction(down/side/up),
-- projects(own/list/all)+project_ids, skill. Ränge/Kategorien reuse ai_position_rank/ai_position_category (generisch).

-- Eigener Mitarbeiter-Datensatz des Aufrufers (über app_users.employee_id).
create or replace function public.perm_caller_emp_id(p_uid uuid default auth.uid())
returns uuid language sql stable security definer set search_path=public as $$
  select employee_id from public.app_users where user_id=p_uid
$$;

create or replace function public.perm_caller_rank(p_uid uuid default auth.uid())
returns integer language sql stable security definer set search_path=public as $$
  select coalesce(public.ai_position_rank((select position from public.employees where id=public.perm_caller_emp_id(p_uid))), 100)
$$;

-- Skills des Aufrufers (eigener Projekt-Skill); null-Skill bleibt tolerant.
create or replace function public.perm_caller_skills(p_uid uuid default auth.uid())
returns text[] language sql stable security definer set search_path=public as $$
  select array(select distinct s from (
    select coalesce(project_skill, skill) s from public.employees where id=public.perm_caller_emp_id(p_uid)
  ) x where s is not null)
$$;

create or replace function public.perm_area_has_skill(p_area text)
returns boolean language sql stable set search_path=public as $$
  select coalesce((select (axes->>'skill')::boolean from public.permission_areas where key=p_area), false)
$$;

-- Erlaubte Projekte des Aufrufers für einen Bereich. null = alle.
create or replace function public.perm_allowed_projects(p_uid uuid, p_area text)
returns text[] language plpgsql stable security definer set search_path=public as $$
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

-- Darf der Aufrufer Daten dieses Projekts (+ Skill) im Bereich sehen?
create or replace function public.perm_proj_ok(p_uid uuid, p_area text, p_project text, p_skill text default null)
returns boolean language plpgsql stable security definer set search_path=public as $$
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

-- Darf der Aufrufer die Gehaltsspalten dieses Mitarbeiters im Bereich sehen? none/own/all.
create or replace function public.perm_salary_ok(p_uid uuid, p_area text, p_emp_id uuid default null)
returns boolean language sql stable security definer set search_path=public as $$
  select case (public.perm(p_uid,p_area)->>'salary')
    when 'all' then true
    when 'own' then p_emp_id is not null and p_emp_id = public.perm_caller_emp_id(p_uid)
    else false end
$$;

-- Darf der Aufrufer diese Mitarbeiter-Zeile im Bereich sehen? Projekt-Scope + Skill + Hierarchie/Richtung + eigene Zeile.
create or replace function public.perm_emp_row_ok(p_uid uuid, p_area text, p_emp_id uuid, p_project text, p_skill text, p_position text)
returns boolean language plpgsql stable security definer set search_path=public as $$
declare crank int; rrank int; dir text;
begin
  if p_emp_id is not null and p_emp_id = public.perm_caller_emp_id(p_uid) then return true; end if;  -- eigene Zeile immer
  if not public.perm_proj_ok(p_uid, p_area, p_project, p_skill) then return false; end if;
  crank := public.perm_caller_rank(p_uid);
  rrank := public.ai_position_rank(p_position);
  dir  := coalesce(public.perm(p_uid,p_area)->>'direction','down');
  if rrank > crank and dir <> 'up'  then return false; end if;   -- höher sehen nur bei 'up' (aufsteigend)
  if rrank = crank and dir =  'down' then return false; end if;   -- 'down' ohne gleiche Ebene
  return true;
end $$;

create or replace function public.perm_mode(p_uid uuid, p_area text)
returns text language sql stable security definer set search_path=public as $$
  select coalesce(public.perm(p_uid,p_area)->>'mode','none')
$$;

-- Ausführbar für authenticated (Views/Policies später); keine Bindung an Policies in diesem Schnitt.
do $$ declare f text; begin
  foreach f in array array[
    'perm_caller_emp_id(uuid)','perm_caller_rank(uuid)','perm_caller_skills(uuid)','perm_area_has_skill(text)',
    'perm_allowed_projects(uuid,text)','perm_proj_ok(uuid,text,text,text)','perm_salary_ok(uuid,text,uuid)',
    'perm_emp_row_ok(uuid,text,uuid,text,text,text)','perm_mode(uuid,text)'] loop
    execute 'grant execute on function public.'||f||' to authenticated';
  end loop;
end $$;
