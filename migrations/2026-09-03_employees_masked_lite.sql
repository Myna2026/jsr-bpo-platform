-- Schlanker Mitarbeiter-Listen-Load. Ursache der 21s-Kaltladung: der Arbeitsvertrag wird als Base64-PDF in
-- extra.contract_file gespeichert (Ø 1,35 MB je MA, 4 MA = 5,2 MB) und flog bei JEDEM Listen-Load mit, obwohl
-- ihn NICHTS im Frontend liest (nur beim Übernehmen geschrieben). employees_masked_lite = identisch zur
-- maskierenden View, aber extra OHNE contract_file. Cuttet den Load ~10× (5,8 → 0,6 MB). Kein Leser betroffen,
-- weil contract_file nirgends gelesen wird. Die volle View employees_masked bleibt für den Vollzugriff bestehen.
-- security_invoker erbt die Zeilen-/Maskier-Logik der Basis-View.
create or replace view public.employees_masked_lite with (security_invoker = true) as
select
  id, first_name, last_name, email, phone, staff_number, role_keys, project_id, skill, target_role, status, source,
  cv_skills, hire_date, termination_date, location, photo_url, about_text, interests, notes, salary_type, hourly_rate,
  work_model, work_hours, shift_earliest, shift_latest, vacation_days, absences, audios, videos, warnings,
  project_assignments, allowed_shifts, bank, contract, (extra - 'contract_file') as extra, created_at, updated_at,
  abilities, bonuses, referrals, quality_ratings, hardware, "position", city, id_number, project_skill, primary_skill,
  photo_color, fixed_salary, guaranteed_pct, deduct_missing, free_days_month, overtime_allowed, productive_pct,
  forecast_include, efficiency_override_pct, age, gender, education, education_level, experience_years, language_level,
  writing_level, languages_str, dream, hobbies, favorite_food, travel_wish, birthday, work_holidays, work_saturday,
  work_sunday, work_split, work_notes, training_id, staff_number_old, import_source, kpi_exempt,
  overhead_productive_pct, email_internal, salary_currency, status_changed_at
from public.employees_masked;

grant select on public.employees_masked_lite to authenticated;
