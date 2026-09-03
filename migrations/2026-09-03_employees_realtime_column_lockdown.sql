-- Punkt 1b: Zweite Tuer schliessen, die Realtime-Publikation.
--
-- Befund: Realtime (postgres_changes) liefert die ROH-Zeile an jeden Abonnenten, der die
-- Zeilen-RLS-Policy passiert, und ignoriert Spalten-Grants. salary='all'-Abonnenten (HR)
-- bekamen damit bei jeder employees-Aenderung die vollen Gehalts-/Bank-/Ausweisfelder auch
-- geschuetzter (Management-)Zeilen frei Haus, an der Masking-View vorbei, obwohl der
-- Direktzugriff aus Cut 1a bereits gesperrt ist.
--
-- Fix: Die Realtime-Publikation von employees wird auf die unsensiblen Spalten begrenzt
-- (PG17 + Replica Identity = PK erlauben Spaltenlisten; die Policy referenziert nur id, das
-- enthalten ist, also bleibt die RLS-Auswertung intakt). Realtime-Events tragen danach nie
-- wieder Gehalt/Bank/Vertrag/Ausweis. Das Frontend laedt die betroffene Zeile bei einem
-- Event frisch und korrekt maskiert aus employees_masked_lite nach.

alter publication supabase_realtime drop table public.employees;

alter publication supabase_realtime add table public.employees (
  id, first_name, last_name, email, phone, staff_number, role_keys, project_id, skill,
  target_role, status, source, cv_skills, hire_date, termination_date, location, photo_url,
  about_text, interests, notes, salary_type, work_model, work_hours, shift_earliest,
  shift_latest, vacation_days, absences, audios, videos, warnings, project_assignments,
  allowed_shifts, extra, created_at, updated_at, abilities, bonuses, referrals,
  quality_ratings, hardware, "position", city, project_skill, primary_skill, photo_color,
  guaranteed_pct, deduct_missing, free_days_month, overtime_allowed, productive_pct,
  forecast_include, efficiency_override_pct, age, gender, education, education_level,
  experience_years, language_level, writing_level, languages_str, dream, hobbies,
  favorite_food, travel_wish, birthday, work_holidays, work_saturday, work_sunday,
  work_split, work_notes, training_id, staff_number_old, import_source, kpi_exempt,
  overhead_productive_pct, email_internal, status_changed_at
);
