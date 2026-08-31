-- Agenten Round 3, Schnitt 0 (perm-Fundament): Empfänger einer Beobachtung = aktive Nutzer mit passender Rolle UND
-- Sichtrecht aufs Projekt der Beobachtung (perm_proj_ok). mgmt/hr (perm_allowed_projects=null) → alle Projekte;
-- Leads → nur eigenes Projekt; globale Beobachtung (p_project null) → nur all-project-Nutzer (mgmt/hr). Ersetzt die
-- ungescopte ROLE_TARGETS-Verteilung in agent-observe. Damit folgt der Fan-out den Rechten, nicht dem Ausschluss.
create or replace function public.agent_recipients(p_project text, p_area text, p_roles text[])
returns setof uuid language sql stable security definer set search_path=public as $$
  select u.user_id from public.app_users u
  where u.active is not false
    and u.role_keys && p_roles
    and public.perm_proj_ok(u.user_id, p_area, p_project, null)
$$;
grant execute on function public.agent_recipients(text,text,text[]) to authenticated, service_role;
