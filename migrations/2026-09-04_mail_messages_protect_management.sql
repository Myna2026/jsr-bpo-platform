-- Schutz von Management-Personen auf mail_messages ziehen (konsistent mit payslips/employee_documents):
-- HR darf die Mail-Akte / Postfach-Mails einer Management-Person NICHT sehen, Management schon.
-- is_protected_employee(emp) = Person hat Management-Rolle. Recruiting-Mails (cv_id, employee_id NULL) bleiben
-- für HR sichtbar (employee_id IS NULL -> Schutzbedingung greift nicht). Eigene Mails (employee_id = self) bleiben.
alter policy mm_select on public.mail_messages using (
  is_management()
  or (is_hr() and not (employee_id is not null and is_protected_employee(employee_id)))
  or (cv_id is not null and perm_mode(auth.uid(),'bewerber') <> 'none')
  or (employee_id is not null and employee_id = perm_caller_emp_id())
);

-- Auch Schreiben (gelesen-markieren / zuordnen / in-die-Akte) einer Management-Person für HR sperren.
alter policy mm_update on public.mail_messages
  using (is_management() or (is_hr() and not (employee_id is not null and is_protected_employee(employee_id))))
  with check (is_management() or (is_hr() and not (employee_id is not null and is_protected_employee(employee_id))));
