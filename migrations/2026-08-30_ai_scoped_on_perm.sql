-- Rechte Schnitt 5: ai_scoped-Views nutzen perm_* (je Tabelle passender Bereich). uid via ai_uid() (GUC).

create or replace view ai_scoped.call_criteria as
SELECT id,
    project_id,
    skill,
    category,
    order_index,
    prompt,
    type,
    max_points,
    weight,
    allow_na,
    hint,
    active,
    created_at,
    updated_at,
    agent_hint,
    level_hints,
    compliance_critical
   FROM call_criteria t
  WHERE perm_proj_ok(ai_uid(), 'kpi', project_id, skill);

create or replace view ai_scoped.call_samples as
SELECT id,
    employee_id,
    sampled_date,
    kw,
    year,
    project_id,
    skill,
    criteria_scope,
    call_ref,
    note,
    total_pct,
    status,
    conducted_by,
    conducted_by_name,
    conducted_at,
    created_at,
    total_points,
    max_points,
    feedback_text,
    compliance_failed,
    raw_points
   FROM call_samples t
  WHERE
        CASE
            WHEN (employee_id IS NOT NULL) THEN (EXISTS ( SELECT 1
               FROM employees e
              WHERE ((e.id = t.employee_id) AND perm_emp_row_ok(ai_uid(), 'kpi', e.id, e.project_id, e.skill, e."position"))))
            ELSE perm_proj_ok(ai_uid(), 'kpi', project_id, skill)
        END;

create or replace view ai_scoped.call_scores as
SELECT id,
    sample_id,
    criterion_id,
    order_index,
    category_snapshot,
    prompt_snapshot,
    type_snapshot,
    max_points_snapshot,
    weight_snapshot,
    points,
    na,
    comment,
    created_at,
    level_hints_snapshot,
    compliance_critical_snapshot
   FROM call_scores t
  WHERE (EXISTS ( SELECT 1
           FROM call_samples cs
          WHERE ((cs.id = t.sample_id) AND (((cs.employee_id IS NOT NULL) AND (EXISTS ( SELECT 1
                   FROM employees e
                  WHERE ((e.id = cs.employee_id) AND perm_emp_row_ok(ai_uid(), 'kpi', e.id, e.project_id, e.skill, e."position"))))) OR ((cs.employee_id IS NULL) AND perm_proj_ok(ai_uid(), 'kpi', cs.project_id, cs.skill))))));

create or replace view ai_scoped.cvs as
SELECT id,
    first_name,
    last_name,
    email,
    phone,
    city,
    status,
    project_id,
    target_role,
    source,
    cv_date,
    age,
    gender,
    dialect,
    education,
    education_level,
    experience_years,
    work_history,
    language_level,
    writing_level,
    languages_str,
    homeoffice_pref,
    available_from,
    dream,
    hobbies,
    travel_wish,
    photo_url,
    photo_color,
    better_email,
    better_phone,
    notes,
    is_structured,
    sales_potential,
    test_answers,
    test_scores,
    audios,
    videos,
    ai_reasoning,
    extra,
    created_at,
    updated_at,
    favorite_food,
    birthday,
    primary_skill,
    id_number,
    bank_name,
    bank_account,
    assessed_level,
    hr_rating,
    contract,
    status_changed_at,
    public_code,
    street,
    postal_code,
    country
   FROM cvs t
  WHERE perm_proj_ok(ai_uid(), 'bewerber', project_id, NULL::text);

create or replace view ai_scoped.employees as
SELECT id,
    first_name,
    last_name,
    email,
    phone,
    staff_number,
    role_keys,
    project_id,
    skill,
    target_role,
    status,
    source,
    cv_skills,
    hire_date,
    termination_date,
    location,
    photo_url,
    about_text,
    interests,
    notes,
        CASE
            WHEN perm_salary_ok(ai_uid(), 'emp', id) THEN salary_type
            ELSE NULL::text
        END AS salary_type,
        CASE
            WHEN perm_salary_ok(ai_uid(), 'emp', id) THEN hourly_rate
            ELSE NULL::numeric
        END AS hourly_rate,
    work_model,
    work_hours,
    shift_earliest,
    shift_latest,
    vacation_days,
    absences,
    audios,
    videos,
    warnings,
    project_assignments,
    allowed_shifts,
        CASE
            WHEN perm_salary_ok(ai_uid(), 'emp', id) THEN bank
            ELSE NULL::jsonb
        END AS bank,
    contract,
    extra,
    created_at,
    updated_at,
    abilities,
    bonuses,
    referrals,
    quality_ratings,
    hardware,
    "position",
    city,
    id_number,
    project_skill,
    primary_skill,
    photo_color,
        CASE
            WHEN perm_salary_ok(ai_uid(), 'emp', id) THEN fixed_salary
            ELSE NULL::numeric
        END AS fixed_salary,
        CASE
            WHEN perm_salary_ok(ai_uid(), 'emp', id) THEN guaranteed_pct
            ELSE NULL::numeric
        END AS guaranteed_pct,
    deduct_missing,
    free_days_month,
    overtime_allowed,
    productive_pct,
    forecast_include,
    efficiency_override_pct,
    age,
    gender,
    education,
    education_level,
    experience_years,
    language_level,
    writing_level,
    languages_str,
    dream,
    hobbies,
    favorite_food,
    travel_wish,
    birthday,
    work_holidays,
    work_saturday,
    work_sunday,
    work_split,
    work_notes,
    training_id,
    staff_number_old,
    import_source,
    kpi_exempt,
    overhead_productive_pct,
    email_internal,
        CASE
            WHEN perm_salary_ok(ai_uid(), 'emp', id) THEN salary_currency
            ELSE NULL::text
        END AS salary_currency,
    status_changed_at
   FROM employees e
  WHERE perm_emp_row_ok(ai_uid(), 'emp', id, project_id, skill, "position");

create or replace view ai_scoped.kpi_config as
SELECT id,
    project_id,
    skill,
    name,
    type,
    unit,
    thresholds,
    created_at,
    level,
    is_primary
   FROM kpi_config t
  WHERE perm_proj_ok(ai_uid(), 'kpi', project_id, skill);

create or replace view ai_scoped.kpi_entries as
SELECT id,
    emp_id,
    kw,
    year,
    kpi_id,
    value,
    entered_by,
    ts,
    source
   FROM kpi_entries t
  WHERE (EXISTS ( SELECT 1
           FROM employees e
          WHERE ((e.id = t.emp_id) AND perm_emp_row_ok(ai_uid(), 'kpi', e.id, e.project_id, e.skill, e."position"))));

create or replace view ai_scoped.kpi_project_entries as
SELECT id,
    project_id,
    skill,
    kw,
    year,
    kpi_id,
    value,
    entered_by,
    ts,
    month,
    source
   FROM kpi_project_entries t
  WHERE perm_proj_ok(ai_uid(), 'kpi', project_id, skill);

create or replace view ai_scoped.projects as
SELECT id,
    name,
    client,
    status,
    location,
    rate_active,
    rate_training,
    billing_mode,
    monthly_flat,
    ai_translation_enabled,
    created_at,
    contract_start,
    contract_end,
    language_requirement,
    description,
    monthly_hours_per_agent,
    billing_type,
    minute_rate,
    case_price,
    case_aht_sec,
    cpo_amount,
    cpo_per_hour,
    flat_per_agent,
    productive_hours,
    efficiency_pct,
    training_mode,
    training_flat,
    color,
    allow_global_bogen
   FROM projects p
  WHERE perm_proj_ok(ai_uid(), 'emp', id, NULL::text);

create or replace view ai_scoped.report_forecast as
SELECT id,
    project_id,
    skill,
    year,
    kw,
    fc_hours,
    file_name,
    updated_by,
    updated_at,
    planned_hours
   FROM report_forecast t
  WHERE perm_proj_ok(ai_uid(), 'kpi', project_id, skill);

create or replace view ai_scoped.report_fte as
SELECT id,
    project_id,
    employee_id,
    fte,
    updated_by,
    updated_at
   FROM report_fte t
  WHERE
        CASE
            WHEN (employee_id IS NOT NULL) THEN (EXISTS ( SELECT 1
               FROM employees e
              WHERE ((e.id = t.employee_id) AND perm_emp_row_ok(ai_uid(), 'kpi', e.id, e.project_id, e.skill, e."position"))))
            ELSE perm_proj_ok(ai_uid(), 'kpi', project_id, NULL::text)
        END;

create or replace view ai_scoped.report_longterm as
SELECT id,
    project_id,
    skill,
    start_year,
    start_month,
    rows,
    file_name,
    updated_by,
    updated_at
   FROM report_longterm t
  WHERE perm_proj_ok(ai_uid(), 'kpi', project_id, skill);

create or replace view ai_scoped.report_measures as
SELECT id,
    project_id,
    skill,
    text,
    status,
    comment,
    created_year,
    created_kw,
    done_year,
    done_kw,
    seq,
    created_by,
    created_by_name,
    created_at,
    updated_at
   FROM report_measures t
  WHERE perm_proj_ok(ai_uid(), 'kpi', project_id, skill);

create or replace view ai_scoped.shift_assignments as
SELECT project_id,
    skill,
    employee_id,
    work_date,
    shift_id,
    label,
    shift_value,
    value2,
    net_hours,
    gross_hours,
    pause_duration,
    pause_paid,
    split,
    slots,
    updated_by,
    updated_by_name,
    updated_at,
    shift
   FROM shift_assignments t
  WHERE
        CASE
            WHEN (employee_id IS NOT NULL) THEN (EXISTS ( SELECT 1
               FROM employees e
              WHERE ((e.id = t.employee_id) AND perm_emp_row_ok(ai_uid(), 'shift', e.id, e.project_id, e.skill, e."position"))))
            ELSE perm_proj_ok(ai_uid(), 'shift', project_id, skill)
        END;

create or replace view ai_scoped.weekly_calls as
SELECT id,
    import_id,
    project_id,
    employee_id,
    kw,
    year,
    answered,
    outbound,
    no_answer,
    avg_handle_sec,
    avg_talk_sec,
    avg_hold_sec,
    avg_acw_sec,
    raw,
    created_at
   FROM weekly_calls t
  WHERE
        CASE
            WHEN (employee_id IS NOT NULL) THEN (EXISTS ( SELECT 1
               FROM employees e
              WHERE ((e.id = t.employee_id) AND perm_emp_row_ok(ai_uid(), 'kpi', e.id, e.project_id, e.skill, e."position"))))
            ELSE perm_proj_ok(ai_uid(), 'kpi', project_id, NULL::text)
        END;

create or replace view ai_scoped.weekly_gauges as
SELECT id,
    import_id,
    project_id,
    employee_id,
    kw,
    year,
    gesamt_pct,
    anzahl,
    dauer_sec,
    nps,
    csat,
    raw,
    created_at
   FROM weekly_gauges t
  WHERE
        CASE
            WHEN (employee_id IS NOT NULL) THEN (EXISTS ( SELECT 1
               FROM employees e
              WHERE ((e.id = t.employee_id) AND perm_emp_row_ok(ai_uid(), 'kpi', e.id, e.project_id, e.skill, e."position"))))
            ELSE perm_proj_ok(ai_uid(), 'kpi', project_id, NULL::text)
        END;

create or replace view ai_scoped.weekly_hours as
SELECT id,
    import_id,
    project_id,
    employee_id,
    kw,
    year,
    skill,
    hours,
    pause_hours,
    raw,
    created_at,
    sales_calls
   FROM weekly_hours t
  WHERE
        CASE
            WHEN (employee_id IS NOT NULL) THEN (EXISTS ( SELECT 1
               FROM employees e
              WHERE ((e.id = t.employee_id) AND perm_emp_row_ok(ai_uid(), 'kpi', e.id, e.project_id, e.skill, e."position"))))
            ELSE perm_proj_ok(ai_uid(), 'kpi', project_id, skill)
        END;

create or replace view ai_scoped.windsor_marketing as
SELECT date,
    datasource,
    account_name,
    source,
    campaign,
    spend,
    impressions,
    clicks,
    reach,
    followers_count
   FROM windsor_marketing t
  WHERE ((perm_allowed_projects(ai_uid(), 'datenpflege') IS NULL) OR (perm_allowed_projects(ai_uid(), 'datenpflege') IS NULL));
