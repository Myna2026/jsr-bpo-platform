-- Arbeitsverteilung Schnitt 2b: Vertretung ("uebernehmen, dann abhaken"). Server-seitige Berechtigung +
-- korrekte Zuschreibung (Zustaendiger bleibt, done_by = Eingesprungener). Schreiben laeuft ueber SECURITY-
-- DEFINER-RPCs, damit die Regel (selbes Projekt / Management / Hierarchie) hart durchgesetzt wird.

-- task_takeover-Unique muss den urspruenglich Zustaendigen einschliessen: sonst kollidieren zwei Vertretungen
-- derselben (task_key,projekt,tag)-Aufgabe verschiedener Personen. Tabelle ist leer -> gefahrlos.
alter table public.task_takeover drop constraint if exists task_takeover_uniq;
alter table public.task_takeover add constraint task_takeover_uniq
  unique nulls not distinct (task_key, project_id, date, orig_assignee);

-- Darf der Aufrufer fuer diese Instanz einspringen? Management ueberall; man selbst; sonst nur bei
-- projektbezogenen Aufgaben, wenn man Planer im SELBEN Projekt ist (deckt Teamleiter/Projektleiter ihres Teams).
create or replace function public.task_can_substitute(p_project_id text, p_orig_assignee uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select is_management()
      or (p_orig_assignee = auth.uid())
      or (p_project_id is not null and is_planner() and p_project_id = get_my_employee_project_id());
$$;

-- Uebernehmen: macht die Vertretung sichtbar (Zustaendiger bleibt orig_assignee, taken_over_by = ich).
create or replace function public.task_take_over(p_task_key text, p_project_id text, p_date date, p_orig_assignee uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.task_can_substitute(p_project_id, p_orig_assignee) then
    raise exception 'not authorized to take over this task';
  end if;
  insert into public.task_takeover(task_key, project_id, date, orig_assignee, taken_over_by)
  values (p_task_key, p_project_id, p_date, p_orig_assignee, auth.uid())
  on conflict (task_key, project_id, date, orig_assignee)
  do update set taken_over_by=auth.uid(), taken_over_at=now();
end; $$;

-- Erledigt setzen/zuruecknehmen fuer eine Instanz (auch fremde, wenn berechtigt). Zustaendiger = p_assignee_user
-- bleibt erhalten, done_by = Aufrufer -> Uebersicht zeigt "zustaendig X / erledigt von Y".
create or replace function public.task_toggle_done(p_task_key text, p_date date, p_assignee_user uuid, p_project_id text, p_done boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not (p_assignee_user = auth.uid() or public.task_can_substitute(p_project_id, p_assignee_user)) then
    raise exception 'not authorized';
  end if;
  if p_done then
    insert into public.daily_tasks_done(task_key, date, assignee_user, project_id, done_by, done_by_name, done_at)
    values (p_task_key, p_date, p_assignee_user, p_project_id, auth.uid(),
            coalesce((select full_name from public.app_users where user_id=auth.uid()), 'jemand'), now())
    on conflict (task_key, date, assignee_user, project_id)
    do update set done_by=auth.uid(), done_by_name=excluded.done_by_name, done_at=now();
  else
    delete from public.daily_tasks_done
     where task_key=p_task_key and date=p_date
       and assignee_user is not distinct from p_assignee_user
       and project_id is not distinct from p_project_id;
  end if;
end; $$;

grant execute on function public.task_can_substitute(text, uuid) to authenticated;
grant execute on function public.task_take_over(text, text, date, uuid) to authenticated;
grant execute on function public.task_toggle_done(text, date, uuid, text, boolean) to authenticated;
