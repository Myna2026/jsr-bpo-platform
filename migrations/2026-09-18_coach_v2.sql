-- Coach v2: Fragenbank neu (Prüfer-Note je Frage), Einstellungen je Partner. Alte Bank wird gelöscht (nur Testdaten hingen dran).
alter table public.coach_questions add column if not exists quality int;          -- Prüfer 1..5 (nur >= 4 aktiv)
alter table public.coach_questions add column if not exists judge_note text;
alter table public.coach_questions add column if not exists gen_version int not null default 1;

create table if not exists public.coach_settings (
  project_id        text primary key,
  default_minutes   int not null default 5 check (default_minutes in (2,5,10,15)),
  default_difficulty text not null default 'mix' check (default_difficulty in ('leicht','mittel','schwer','mix')),
  allowed_kinds     text[] not null default array['mc','gap','match','order','free'],
  hidden_topics     text[] not null default '{}',
  topic_cap         int not null default 40,       -- höchstens so viele aktive Fragen je Thema und Art
  show_timer        boolean not null default true,
  updated_by        uuid, updated_at timestamptz not null default now()
);
alter table public.coach_settings enable row level security;
drop policy if exists coach_settings_read on public.coach_settings;
create policy coach_settings_read on public.coach_settings for select to authenticated using (true);
drop policy if exists coach_settings_write on public.coach_settings;
create policy coach_settings_write on public.coach_settings for all to authenticated
  using (perm_mode(auth.uid(),'wissen') = 'edit' and perm_proj_ok(auth.uid(),'wissen',project_id))
  with check (perm_mode(auth.uid(),'wissen') = 'edit' and perm_proj_ok(auth.uid(),'wissen',project_id));

-- coach_available: Einstellungen mitgeben, versteckte Themen aus Matrix/Listen lassen
create or replace function public.coach_available()
returns jsonb language sql stable security definer set search_path = public as $$
  with st as (select * from coach_settings where project_id = public.get_my_employee_project_id()),
       q as (select * from coach_questions q where q.project_id = public.get_my_employee_project_id() and q.status = 'active'
               and not (q.topic = any(coalesce((select hidden_topics from st), '{}'::text[])))
               and q.kind = any(coalesce((select allowed_kinds from st), array['mc','gap','match','order','free'])))
  select jsonb_build_object('project_id', public.get_my_employee_project_id(),
    'questions', (select count(*) from q),
    'topics', (select coalesce(jsonb_agg(t order by t), '[]'::jsonb) from (select distinct topic as t from q) x),
    'zielgebiete', (select coalesce(jsonb_agg(z order by z), '[]'::jsonb) from (select distinct zielgebiet as z from q where zielgebiet is not null) y),
    'matrix', (select coalesce(jsonb_agg(jsonb_build_object('t',topic,'z',zielgebiet,'d',difficulty,'k',kind,'n',n)), '[]'::jsonb)
               from (select topic, zielgebiet, difficulty, kind, count(*) as n from q group by 1,2,3,4) m),
    'settings', (select coalesce(to_jsonb(st), '{}'::jsonb) from st),
    'today', (select count(*) from coach_sessions s where s.employee_id = public.get_my_employee_id() and s.status = 'done' and s.finished_at::date = current_date),
    'assignments', (select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'topic',a.topic,'zielgebiet',a.zielgebiet,'minutes',a.minutes,'difficulty',a.difficulty,'due_date',a.due_date,'note',a.note,'assigned_by_name',a.assigned_by_name,'overdue',(a.due_date is not null and a.due_date < current_date)) order by a.due_date nulls last, a.created_at), '[]'::jsonb)
                     from coach_assignments a where a.employee_id = public.get_my_employee_id() and a.status = 'open'));
$$;
