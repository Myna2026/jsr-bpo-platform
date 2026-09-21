-- Kundenportal: Register (kb_facts) und Dokumenttitel des eigenen Projekts nur lesen (Durchblättern bei Conny). Kein Schreiben.
drop policy if exists kb_facts_client_sel on public.kb_facts;
create policy kb_facts_client_sel on public.kb_facts for select to authenticated
  using (status = 'active' and public.get_my_client_project_id() is not null and project_id = public.get_my_client_project_id());
drop policy if exists kb_documents_client_sel on public.kb_documents;
create policy kb_documents_client_sel on public.kb_documents for select to authenticated
  using (public.get_my_client_project_id() is not null and project_id = public.get_my_client_project_id());
drop policy if exists kb_regions_client_sel on public.kb_regions;
create policy kb_regions_client_sel on public.kb_regions for select to authenticated
  using (status = 'active' and public.get_my_client_project_id() is not null and project_id = public.get_my_client_project_id());
