-- ============================================================================
-- TIVE 360° — Team-Chat NACHTRAG (Teil 2): RPCs für Übersetzungs-Cache + Gruppen-Admin.
-- Ergänzt 2026-07-26_team_chat.sql. Idempotent. Im Supabase SQL Editor einspielen.
--
-- Warum getrennt: Der Code (Schritt 2) braucht diese 5 RPCs für Übersetzung-Persistenz
-- und Gruppen-Verwaltung (umbenennen/hinzufügen/entfernen/verlassen). Der Kern-Chat
-- (Thread öffnen, Gruppe anlegen/beitreten, Senden, Lesestatus) läuft schon ohne sie.
-- ============================================================================

-- Übersetzungs-Cache: der SENDER aktualisiert translations seiner eigenen Nachricht.
create or replace function public.dm_set_translations(p_msg uuid, p_tr jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid;
begin
  me := public.get_my_employee_id();
  if me is null then raise exception 'keine employee-Identität'; end if;
  update public.dm_messages
     set translations = coalesce(p_tr, '{}'::jsonb)
   where id = p_msg and from_emp_id = me;   -- nur eigene Nachricht
end; $$;

-- Gruppe umbenennen — nur Ersteller.
create or replace function public.dm_rename_group(p_thread uuid, p_name text)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid;
begin
  me := public.get_my_employee_id();
  update public.dm_threads
     set name = coalesce(nullif(trim(p_name), ''), name)
   where id = p_thread and is_group and created_by = me;
  if not found then raise exception 'nur der Ersteller darf umbenennen'; end if;
end; $$;

-- Mitglied hinzufügen — nur Ersteller, und nur wer chatberechtigt ist.
create or replace function public.dm_add_member(p_thread uuid, p_emp uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid;
begin
  me := public.get_my_employee_id();
  if not exists (select 1 from public.dm_threads where id = p_thread and is_group and created_by = me)
    then raise exception 'nur der Ersteller darf Mitglieder hinzufügen'; end if;
  if not public.dm_can_chat(p_emp) then raise exception 'Kontakt nicht erlaubt'; end if;
  insert into public.dm_participants(thread_id, emp_id) values (p_thread, p_emp) on conflict do nothing;
end; $$;

-- Mitglied entfernen — nur Ersteller, nicht sich selbst.
create or replace function public.dm_remove_member(p_thread uuid, p_emp uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid;
begin
  me := public.get_my_employee_id();
  if p_emp = me then raise exception 'sich selbst nicht entfernen — Gruppe verlassen'; end if;
  if not exists (select 1 from public.dm_threads where id = p_thread and is_group and created_by = me)
    then raise exception 'nur der Ersteller darf Mitglieder entfernen'; end if;
  delete from public.dm_participants where thread_id = p_thread and emp_id = p_emp;
end; $$;

-- Gruppe verlassen — sich selbst entfernen; leere Gruppe wird gelöscht (cascade → messages/reads).
create or replace function public.dm_leave_group(p_thread uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid; n int;
begin
  me := public.get_my_employee_id();
  if me is null then raise exception 'keine employee-Identität'; end if;
  delete from public.dm_participants where thread_id = p_thread and emp_id = me;
  select count(*) into n from public.dm_participants where thread_id = p_thread;
  if n = 0 then delete from public.dm_threads where id = p_thread; end if;
end; $$;

revoke all on function public.dm_set_translations(uuid,jsonb) from public;
revoke all on function public.dm_rename_group(uuid,text)      from public;
revoke all on function public.dm_add_member(uuid,uuid)        from public;
revoke all on function public.dm_remove_member(uuid,uuid)     from public;
revoke all on function public.dm_leave_group(uuid)            from public;
grant execute on function public.dm_set_translations(uuid,jsonb) to authenticated;
grant execute on function public.dm_rename_group(uuid,text)      to authenticated;
grant execute on function public.dm_add_member(uuid,uuid)        to authenticated;
grant execute on function public.dm_remove_member(uuid,uuid)     to authenticated;
grant execute on function public.dm_leave_group(uuid)            to authenticated;
