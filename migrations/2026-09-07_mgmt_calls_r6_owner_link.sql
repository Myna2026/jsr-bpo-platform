-- Management-Calls R6: Die KI erkennt die zuständige Person aus dem Freitext ("Edi macht das") und gleicht
-- sie gegen die Mitarbeiter ab -> echter Datensatz statt loser Name. Optionaler Link, additiv.
-- Kein Name im Text -> Punkt bleibt allgemein für die Runde (owner + owner_employee_id null).

alter table public.mgmt_call_items add column if not exists owner_employee_id uuid
  references public.employees(id) on delete set null;
create index if not exists mgmt_call_items_owner_emp_idx on public.mgmt_call_items(owner_employee_id);
