-- Coach S7: Pflichteinheiten (Zuweisung durch uns oder die Teamleitung) + Probelauf im HR-Portal (ohne Speichern).
create table if not exists public.coach_assignments (
  id               uuid primary key default gen_random_uuid(),
  project_id       text not null,
  employee_id      uuid not null references public.employees(id) on delete cascade,
  topic            text,                                  -- null = Mix aus allem
  zielgebiet       text,
  minutes          int not null default 5 check (minutes in (2,5,10,15)),
  difficulty       text not null default 'mix' check (difficulty in ('leicht','mittel','schwer','mix')),
  due_date         date,
  note             text,
  assigned_by      uuid, assigned_by_name text,
  status           text not null default 'open' check (status in ('open','done','cancelled')),
  session_id       uuid references public.coach_sessions(id) on delete set null,
  done_at          timestamptz,
  created_at       timestamptz not null default now()
);
create index if not exists coach_assign_emp on public.coach_assignments(employee_id, status);
create index if not exists coach_assign_proj on public.coach_assignments(project_id, status);
alter table public.coach_sessions add column if not exists assignment_id uuid references public.coach_assignments(id) on delete set null;
alter table public.coach_assignments enable row level security;

-- Mitarbeiter: eigene lesen
drop policy if exists coach_as_own on public.coach_assignments;
create policy coach_as_own on public.coach_assignments for select to authenticated using (employee_id = public.get_my_employee_id());
-- Wir (Bereich wissen, bearbeiten) und die Teamleitung des Projekts: alles
drop policy if exists coach_as_internal on public.coach_assignments;
create policy coach_as_internal on public.coach_assignments for all to authenticated
  using ((perm_mode(auth.uid(),'wissen') = 'edit' and perm_proj_ok(auth.uid(),'wissen',project_id))
      or (public.is_planner() and project_id = public.get_my_employee_project_id()))
  with check ((perm_mode(auth.uid(),'wissen') = 'edit' and perm_proj_ok(auth.uid(),'wissen',project_id))
      or (public.is_planner() and project_id = public.get_my_employee_project_id()));
-- Kunde: kein Zugriff (Zuweisungen sind Führungssache)

-- coach_available: offene Pflichteinheiten mitgeben (fürs MA-Menü)
create or replace function public.coach_available()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('project_id', public.get_my_employee_project_id(),
    'questions', (select count(*) from coach_questions q where q.project_id = public.get_my_employee_project_id() and q.status = 'active'),
    'topics', (select coalesce(jsonb_agg(t order by t), '[]'::jsonb) from (select distinct topic as t from coach_questions q where q.project_id = public.get_my_employee_project_id() and q.status = 'active') x),
    'zielgebiete', (select coalesce(jsonb_agg(z order by z), '[]'::jsonb) from (select distinct zielgebiet as z from coach_questions q where q.project_id = public.get_my_employee_project_id() and q.status = 'active' and zielgebiet is not null) y),
    'today', (select count(*) from coach_sessions s where s.employee_id = public.get_my_employee_id() and s.status = 'done' and s.finished_at::date = current_date),
    'assignments', (select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'topic',a.topic,'zielgebiet',a.zielgebiet,'minutes',a.minutes,'difficulty',a.difficulty,'due_date',a.due_date,'note',a.note,'assigned_by_name',a.assigned_by_name,'overdue',(a.due_date is not null and a.due_date < current_date)) order by a.due_date nulls last, a.created_at), '[]'::jsonb)
                     from coach_assignments a where a.employee_id = public.get_my_employee_id() and a.status = 'open'));
$$;
