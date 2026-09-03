-- Punkt 1a: Basistabelle employees als Direkt-Lesequelle fuer sensible Felder schliessen.
--
-- Befund (bewiesen): Die Basistabelle employees ist fuer authenticated direkt lesbar,
-- ihre SELECT-Policy filtert Zeilen nur ueber perm_salary_ok (Gehalts-Erlaubnis), nicht
-- ueber Projekt und nicht ueber is_protected_employee. Wer salary='all' hat (HR), konnte
-- damit an der Masking-View vorbei jedes Gehalt/IBAN direkt aus der Basistabelle lesen
-- (verifiziert: HR liest Management-Gehalt 3000 + IBAN, obwohl die View sie verbirgt).
--
-- Fix: Die 6 sensiblen Spalten (Gehalt, Stundenlohn, Waehrung, Bank, Vertrag, Ausweis)
-- werden dem authenticated/anon-Direktzugriff auf die Basistabelle entzogen. Sie sind
-- danach NUR noch ueber die security-definer-Masking-View (employees_masked/_lite) lesbar,
-- die die Sichtbarkeitsregeln (Management/Finance/voll/protected/operativ) korrekt anwendet.
--
-- Alle unsensiblen Spalten (Name, Projekt, Status, ...) bleiben direkt lesbar, damit die
-- vorhandenen Policy-Subqueries anderer Tabellen (kpi_entries, vacation_requests,
-- activity_log, feedback_*) und die Namens-/Zaehler-Reads im Frontend unveraendert weiter
-- funktionieren (die lesen ausschliesslich project_id/id/name). Die Zeilen-Sichtbarkeit
-- (RLS-Policy) bleibt unangetastet, es aendern sich nur die lesbaren Spalten.

-- 1) Eigen-Datensatz-View: Nach dem Spalten-Entzug kann ein Mitarbeiter seine EIGENE Zeile
--    (inkl. eigenem Gehalt/Bank) nicht mehr direkt aus der Basistabelle lesen. Diese
--    definer-View gibt ausschliesslich die eigene Zeile des Aufrufers voll zurueck.
create or replace view public.employees_self as
  select * from public.employees where id = public.perm_caller_emp_id();

grant select on public.employees_self to authenticated;

-- 2) Basistabelle: Table-SELECT entziehen, danach nur die unsensiblen Spalten neu granten.
--    (Column-level-Restriction verlangt den Entzug des Table-Grants, weil ein Table-Grant
--     Column-Grants dominiert.) INSERT/UPDATE/DELETE bleiben unveraendert.
revoke select on public.employees from authenticated, anon;

grant select (
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
) on public.employees to authenticated;
