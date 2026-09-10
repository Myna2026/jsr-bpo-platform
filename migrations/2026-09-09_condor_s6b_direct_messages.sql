-- Condor S6b: Der Kunde kann einzelne Mitarbeiter direkt ansprechen, nicht nur die Teamleitung.
--   recipient_employee_id = null  → Team-Kanal (wie bisher, Kunde ↔ Teamleitung)
--   recipient_employee_id gesetzt → Direktkanal Kunde ↔ diesem Mitarbeiter
-- Der angeschriebene MA liest/antwortet in seinem Portal (from_side='employee').
-- Teamleitung/HR/Management sehen JEDEN Faden mit (Aufsicht) — nichts läuft an der Führung vorbei.

alter table public.client_team_messages
  add column if not exists recipient_employee_id uuid references public.employees(id) on delete cascade;

-- from_side um 'employee' erweitern (Antwort des angeschriebenen Mitarbeiters).
alter table public.client_team_messages drop constraint if exists client_team_messages_from_side_check;
alter table public.client_team_messages
  add constraint client_team_messages_from_side_check check (from_side in ('client','team','employee'));

create index if not exists client_team_messages_recip_idx
  on public.client_team_messages(recipient_employee_id, sent_at);

-- Darf der Kunde diesen MA anschreiben? (MA muss auf dem Projekt des Kunden aktiv sein.)
-- security_definer, weil der Kunde keinen Basiszugriff auf employees hat.
create or replace function public.ctm_recipient_ok(p_emp uuid, p_project text)
returns boolean language sql stable security definer set search_path=public as $$
  select p_emp is null
      or exists (
        select 1 from public.employees e
        where e.id = p_emp and e.project_id = p_project
          and e.status in ('active','training')
      );
$$;
revoke all    on function public.ctm_recipient_ok(uuid,text) from public;
grant execute on function public.ctm_recipient_ok(uuid,text) to authenticated;

-- SELECT: bisherige Mitleser (Kunde des Projekts, Management/HR, Teamleitung/Projektleiter des Projekts)
-- sehen ALLES inkl. Direktfäden. Zusätzlich: der angeschriebene MA sieht seinen eigenen Faden.
drop policy if exists ctm_select on public.client_team_messages;
create policy ctm_select on public.client_team_messages for select to authenticated
  using (
    (public.get_my_client_project_id() is not null and project_id = public.get_my_client_project_id())
    or public.is_management() or public.is_hr()
    or (public.is_planner() and public.get_my_employee_project_id() = project_id)
    or (recipient_employee_id is not null and recipient_employee_id = public.my_employee_id())
  );

-- Kunde schreibt from_side='client' fürs eigene Projekt; Empfänger null (Team) oder ein MA auf dem Projekt.
drop policy if exists ctm_insert_client on public.client_team_messages;
create policy ctm_insert_client on public.client_team_messages for insert to authenticated
  with check (
    from_side = 'client'
    and public.get_my_client_project_id() is not null
    and project_id = public.get_my_client_project_id()
    and public.ctm_recipient_ok(recipient_employee_id, project_id)
  );

-- Team (Teamleitung / Management / HR) schreibt from_side='team' fürs zugehörige Projekt (unverändert,
-- darf auch in einen Direktfaden mitschreiben).
drop policy if exists ctm_insert_team on public.client_team_messages;
create policy ctm_insert_team on public.client_team_messages for insert to authenticated
  with check (
    from_side = 'team'
    and ( public.is_management() or public.is_hr()
          or (public.is_planner() and public.get_my_employee_project_id() = project_id) )
  );

-- Der angeschriebene MA antwortet: from_side='employee', nur im eigenen Faden, nur fürs eigene Projekt.
drop policy if exists ctm_insert_employee on public.client_team_messages;
create policy ctm_insert_employee on public.client_team_messages for insert to authenticated
  with check (
    from_side = 'employee'
    and recipient_employee_id is not null
    and recipient_employee_id = public.my_employee_id()
    and project_id = public.get_my_employee_project_id()
  );
