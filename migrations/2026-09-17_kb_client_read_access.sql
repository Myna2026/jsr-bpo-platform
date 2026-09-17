-- Conny im Kundenportal: Kundenzugänge (Rolle kunde) dürfen den Wissensspeicher ihres Projekts LESEN (fragen),
-- nichts einspeisen oder ändern ('read' erlaubt kein Schreiben; kb_facts/kb_documents/kb_chunks/kb_regions/
-- kb_change_propose verlangen alle perm_mode = 'edit').
-- Projekt-Auflösung 'own' kannte bisher nur den Mitarbeiter-Datensatz; Kundenzugänge haben keinen → neuer Zweig:
-- kein Mitarbeiter, aber Kundenkonto → dessen Projekt. Wirkt nur auf Zugänge ohne Mitarbeiter-Datensatz.
insert into public.role_permissions(role_key,area_key,visible,mode,salary,direction,projects,skill) values
 ('kunde','wissen',true,'read','none','down','own','all')
on conflict (role_key,area_key) do nothing;

create or replace function public.perm_allowed_projects(p_uid uuid, p_area text)
returns text[] language plpgsql stable security definer set search_path = public as $$
declare pr jsonb; scope text; emp text[]; cli text;
begin
  pr := public.perm(p_uid, p_area); scope := pr->>'projects';
  if scope = 'all' then return null; end if;                              -- alle Projekte
  if scope = 'list' then
    return coalesce((select array(select jsonb_array_elements_text(pr->'project_ids'))), '{}'::text[]);
  end if;
  -- 'own' (Default): nur das eigene Projekt (Mitarbeiter-Datensatz), sonst das Projekt des Kundenkontos
  emp := (select array[project_id] from public.employees where id=public.perm_caller_emp_id(p_uid) and project_id is not null);
  if emp is not null then return emp; end if;
  select c.project_id into cli from public.app_users u join public.client_accounts c on c.id = u.client_id where u.user_id = p_uid and c.project_id is not null limit 1;
  if cli is not null then return array[cli]; end if;
  return '{}'::text[];
end $$;
