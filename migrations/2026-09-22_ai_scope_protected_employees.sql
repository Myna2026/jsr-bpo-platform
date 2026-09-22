-- Datenabfrage (ai_scoped): Management-Personen sind auch hier geschützt.
-- Bisher entschied allein perm_salary_ok('all'); HR (z. B. Deonita) hätte über die Abfrage Gehalt, Bank, Vertrag und
-- Ausweisnummer der Management-Personen gesehen, obwohl employees_masked genau das im HR-Portal verbirgt.
-- Regel jetzt identisch zur Portal-Sicht: Management/Finance sehen alles; alle anderen sehen bei geschützten Personen
-- (app_users.role_keys enthält 'management') kein fixed_salary/hourly_rate/salary_currency/bank/contract/id_number.
create or replace function public.ai_is_mgmt_or_finance(p_uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from app_users a where a.user_id = p_uid and a.role_keys && array['management','finance']);
$$;
-- true = der Abfragende darf die Gehalts-/Vertragsspalten dieser Person sehen
create or replace function public.ai_salary_ok(p_uid uuid, p_emp_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.perm_salary_ok(p_uid, 'emp', p_emp_id)
     and (public.ai_is_mgmt_or_finance(p_uid)
          or p_emp_id = public.perm_caller_emp_id(p_uid)
          or not public.is_protected_employee(p_emp_id));
$$;
grant execute on function public.ai_is_mgmt_or_finance(uuid), public.ai_salary_ok(uuid, uuid) to authenticated, service_role, agent_ro;

create or replace view ai_scoped.employees as
 select id, first_name, last_name, email, phone, staff_number, role_keys, project_id, skill, target_role, status, source,
    cv_skills, hire_date, termination_date, location, photo_url, about_text, interests, notes,
    case when public.ai_salary_ok(public.ai_uid(), id) then salary_type else null::text end as salary_type,
    case when public.ai_salary_ok(public.ai_uid(), id) then hourly_rate else null::numeric end as hourly_rate,
    work_model, work_hours, shift_earliest, shift_latest, vacation_days, absences, audios, videos, warnings,
    project_assignments, allowed_shifts,
    case when public.ai_salary_ok(public.ai_uid(), id) then bank else null::jsonb end as bank,
    case when public.ai_salary_ok(public.ai_uid(), id) then contract else null::jsonb end as contract,
    extra, created_at, updated_at, abilities, bonuses, referrals, quality_ratings, hardware, "position", city,
    case when public.ai_salary_ok(public.ai_uid(), id) then id_number else null::text end as id_number,
    project_skill, primary_skill, photo_color,
    case when public.ai_salary_ok(public.ai_uid(), id) then fixed_salary else null::numeric end as fixed_salary,
    case when public.ai_salary_ok(public.ai_uid(), id) then guaranteed_pct else null::numeric end as guaranteed_pct,
    deduct_missing, free_days_month, overtime_allowed, productive_pct, forecast_include, efficiency_override_pct,
    age, gender, education, education_level, experience_years, language_level, writing_level, languages_str,
    dream, hobbies, favorite_food, travel_wish, birthday, work_holidays, work_saturday, work_sunday, work_split,
    work_notes, training_id, staff_number_old, import_source, kpi_exempt, overhead_productive_pct, email_internal,
    case when public.ai_salary_ok(public.ai_uid(), id) then salary_currency else null::text end as salary_currency,
    status_changed_at
   from employees e
  where public.perm_emp_row_ok(public.ai_uid(), 'emp', id, project_id, skill, "position");
grant select on ai_scoped.employees to agent_ro, authenticated, service_role;
