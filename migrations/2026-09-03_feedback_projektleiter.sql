-- Feedbackgespräche für Projektleiter freigeben — projektbezogen (nur ihr eigenes Projekt). Bislang nur is_admin()
-- (Management/HR) + Mitarbeiter-eigene Sicht; Projektleiter (Edi=HolidayCheck, Ylli=Giganetz) hatten keinen Zugriff,
-- der Menüpunkt war offen, aber die RLS blockierte die Daten. Scope: Session-Projekt = eigenes Projekt (Fallback:
-- Projekt des bewerteten Mitarbeiters). Fragenkatalog nur lesen (Bearbeitung bleibt Admin). is_planner() =
-- projektleiter/teamlead; get_my_employee_project_id() = eigenes Projekt. Idempotent.

-- feedback_sessions: Projektleiter volle Rechte auf Sessions seines Projekts.
drop policy if exists feedback_sessions_lead on public.feedback_sessions;
create policy feedback_sessions_lead on public.feedback_sessions for all to authenticated
  using ( public.is_planner() and coalesce(project_id,(select e.project_id from public.employees e where e.id=feedback_sessions.employee_id)) = public.get_my_employee_project_id() )
  with check ( public.is_planner() and coalesce(project_id,(select e.project_id from public.employees e where e.id=feedback_sessions.employee_id)) = public.get_my_employee_project_id() );

-- feedback_answers: über die zugehörige Session projektbezogen.
drop policy if exists feedback_answers_lead on public.feedback_answers;
create policy feedback_answers_lead on public.feedback_answers for all to authenticated
  using ( exists (select 1 from public.feedback_sessions s where s.id=feedback_answers.session_id and public.is_planner()
                  and coalesce(s.project_id,(select e.project_id from public.employees e where e.id=s.employee_id)) = public.get_my_employee_project_id()) )
  with check ( exists (select 1 from public.feedback_sessions s where s.id=feedback_answers.session_id and public.is_planner()
                  and coalesce(s.project_id,(select e.project_id from public.employees e where e.id=s.employee_id)) = public.get_my_employee_project_id()) );

-- feedback_questions: Fragenkatalog nur LESEN (zum Gespräch führen); Bearbeitung bleibt Admin.
drop policy if exists feedback_questions_lead_read on public.feedback_questions;
create policy feedback_questions_lead_read on public.feedback_questions for select to authenticated
  using ( public.is_planner() );
