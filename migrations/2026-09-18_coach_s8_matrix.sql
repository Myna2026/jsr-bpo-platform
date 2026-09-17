-- Coach: Auswahl nur, wo es Fragen gibt. coach_available liefert die Verfügbarkeits-Matrix je Thema/Zielgebiet/Stufe/Art.
create or replace function public.coach_available()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('project_id', public.get_my_employee_project_id(),
    'questions', (select count(*) from coach_questions q where q.project_id = public.get_my_employee_project_id() and q.status = 'active'),
    'topics', (select coalesce(jsonb_agg(t order by t), '[]'::jsonb) from (select distinct topic as t from coach_questions q where q.project_id = public.get_my_employee_project_id() and q.status = 'active') x),
    'zielgebiete', (select coalesce(jsonb_agg(z order by z), '[]'::jsonb) from (select distinct zielgebiet as z from coach_questions q where q.project_id = public.get_my_employee_project_id() and q.status = 'active' and zielgebiet is not null) y),
    'matrix', (select coalesce(jsonb_agg(jsonb_build_object('t',topic,'z',zielgebiet,'d',difficulty,'k',kind,'n',n)), '[]'::jsonb)
               from (select topic, zielgebiet, difficulty, kind, count(*) as n from coach_questions q where q.project_id = public.get_my_employee_project_id() and q.status = 'active' group by 1,2,3,4) m),
    'today', (select count(*) from coach_sessions s where s.employee_id = public.get_my_employee_id() and s.status = 'done' and s.finished_at::date = current_date),
    'assignments', (select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'topic',a.topic,'zielgebiet',a.zielgebiet,'minutes',a.minutes,'difficulty',a.difficulty,'due_date',a.due_date,'note',a.note,'assigned_by_name',a.assigned_by_name,'overdue',(a.due_date is not null and a.due_date < current_date)) order by a.due_date nulls last, a.created_at), '[]'::jsonb)
                     from coach_assignments a where a.employee_id = public.get_my_employee_id() and a.status = 'open'));
$$;
