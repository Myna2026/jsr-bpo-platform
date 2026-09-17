-- Coach: Wiederholung im richtigen Abstand. Je Mitarbeiter und Frage ein Lernstand (Leitner-Kästen): richtig → längerer
-- Abstand (1, 3, 7, 14, 30 Tage), falsch → zurück auf Kasten 0 (morgen wieder). Der Motor zieht fällige Fragen zuerst.
create table if not exists public.coach_progress (
  employee_id   uuid not null references public.employees(id) on delete cascade,
  question_id   uuid not null references public.coach_questions(id) on delete cascade,
  box           int not null default 0,
  next_due      timestamptz not null default now(),
  seen          int not null default 0,
  correct       int not null default 0,
  last_points   numeric,
  updated_at    timestamptz not null default now(),
  primary key (employee_id, question_id)
);
create index if not exists coach_progress_due on public.coach_progress(employee_id, next_due);
alter table public.coach_progress enable row level security;
drop policy if exists coach_progress_own on public.coach_progress;
create policy coach_progress_own on public.coach_progress for select to authenticated using (employee_id = public.get_my_employee_id());
drop policy if exists coach_progress_internal on public.coach_progress;
create policy coach_progress_internal on public.coach_progress for select to authenticated
  using (coalesce((perm(auth.uid(),'wissen')->>'visible')::boolean,false) and exists (select 1 from coach_questions q where q.id = question_id and perm_proj_ok(auth.uid(),'wissen',q.project_id)));
