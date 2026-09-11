-- =============================================================================
-- Wurzel-Fix: Bewerber-Vertragsdatei aus der Zeile raus in den Storage.
-- Analog zu employee-docs. Bisher lag der unterschriebene Vertrag als base64
-- in cvs.contract.signed_file (Messung 2026-09-11: 15 MB von 17 MB der cvs-
-- Tabelle steckten dort) -> jede select('*')-Abfrage schleppte ihn mit.
-- Ab jetzt: Datei im privaten Bucket 'cv-docs', in der Zeile nur der Pfad
-- (cvs.contract.signed_path). Zugriff spiegelt exakt die cvs-RLS (perm 'bewerber'
-- + Projekt-Scope) -> wer den Bewerber sieht/bearbeitet, sieht/bearbeitet auch
-- dessen Vertragsdatei. Idempotent.
-- =============================================================================

-- 1) Privater Bucket. PDF + Bilder (das Upload-Feld erlaubt .pdf/.jpg/.png). 10 MB.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('cv-docs', 'cv-docs', false, 10485760,
        array['application/pdf','image/jpeg','image/png'])
on conflict (id) do update
  set public             = false,
      file_size_limit    = 10485760,
      allowed_mime_types = array['application/pdf','image/jpeg','image/png'];

-- 2) Zugriffs-Helper: spiegelt die cvs-RLS fuer die im Pfad steckende cv_id.
--    Pfad-Konvention: <cv_id>/contract/<datei>. p_need='view' (lesen) | 'edit' (schreiben).
--    SECURITY DEFINER, damit die perm-Funktionen unabhaengig von der cvs-RLS zaehlen;
--    auth.uid() bleibt der aufrufende Nutzer. Fail-closed: ungueltige/fehlende id -> false.
create or replace function public.cv_doc_perm(p_cv_id text, p_need text default 'view')
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_cv_id is null
      or p_cv_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then false
    else exists (
      select 1 from public.cvs c
      where c.id = p_cv_id::uuid
        and case when p_need = 'edit'
                 then public.perm_mode(auth.uid(), 'bewerber') = 'edit'
                 else public.perm_mode(auth.uid(), 'bewerber') <> 'none' end
        and public.perm_proj_ok(auth.uid(), 'bewerber', c.project_id, null)
    )
  end;
$$;
revoke all    on function public.cv_doc_perm(text, text) from public;
grant execute on function public.cv_doc_perm(text, text) to authenticated;

-- 3) Policies auf storage.objects, nur fuer Bucket 'cv-docs'. Erste Pfad-Ebene = cv_id.
drop policy if exists cv_docs_select on storage.objects;
create policy cv_docs_select on storage.objects for select to authenticated
  using (bucket_id = 'cv-docs' and public.cv_doc_perm((storage.foldername(name))[1], 'view'));

drop policy if exists cv_docs_insert on storage.objects;
create policy cv_docs_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'cv-docs' and public.cv_doc_perm((storage.foldername(name))[1], 'edit'));

drop policy if exists cv_docs_update on storage.objects;
create policy cv_docs_update on storage.objects for update to authenticated
  using      (bucket_id = 'cv-docs' and public.cv_doc_perm((storage.foldername(name))[1], 'edit'))
  with check (bucket_id = 'cv-docs' and public.cv_doc_perm((storage.foldername(name))[1], 'edit'));

drop policy if exists cv_docs_delete on storage.objects;
create policy cv_docs_delete on storage.objects for delete to authenticated
  using (bucket_id = 'cv-docs' and public.cv_doc_perm((storage.foldername(name))[1], 'edit'));

notify pgrst, 'reload schema';
