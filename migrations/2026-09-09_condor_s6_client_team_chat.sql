-- Condor S6: Kanal Kunde ↔ Teamleitung (ein Kanal je Projekt). NICHT der interne Team-Chat (dm_*), dort
-- besprechen unsere Leute Internes. Sichtbar für: den Kunden (eigenes Projekt), die Teamleitung des Projekts,
-- sowie Management/HR (Aufsicht). Agenten sehen ihn NICHT.

create table if not exists public.client_team_messages (
  id          uuid primary key default gen_random_uuid(),
  project_id  text not null references public.projects(id) on delete cascade,
  from_side   text not null check (from_side in ('client','team')),
  author_uid  uuid,
  author_name text,
  body        text not null,
  sent_at     timestamptz not null default now()
);
create index if not exists client_team_messages_proj_idx on public.client_team_messages(project_id, sent_at);

alter table public.client_team_messages enable row level security;
grant select, insert on public.client_team_messages to authenticated;

-- Wer intern zum Kanal eines Projekts gehört: Management/HR (alle) oder Teamleitung/Projektleiter des Projekts.
-- (is_planner() = mgmt/hr/teamlead/projektleiter; get_my_employee_project_id() scopt Leads auf ihr Projekt.)
drop policy if exists ctm_select on public.client_team_messages;
create policy ctm_select on public.client_team_messages for select to authenticated
  using (
    (public.get_my_client_project_id() is not null and project_id = public.get_my_client_project_id())
    or public.is_management() or public.is_hr()
    or (public.is_planner() and public.get_my_employee_project_id() = project_id)
  );

-- Kunde schreibt from_side='client' fürs eigene Projekt.
drop policy if exists ctm_insert_client on public.client_team_messages;
create policy ctm_insert_client on public.client_team_messages for insert to authenticated
  with check (
    from_side = 'client'
    and public.get_my_client_project_id() is not null
    and project_id = public.get_my_client_project_id()
  );

-- Team (Teamleitung / Management / HR) schreibt from_side='team' fürs zugehörige Projekt.
drop policy if exists ctm_insert_team on public.client_team_messages;
create policy ctm_insert_team on public.client_team_messages for insert to authenticated
  with check (
    from_side = 'team'
    and ( public.is_management() or public.is_hr()
          or (public.is_planner() and public.get_my_employee_project_id() = project_id) )
  );
