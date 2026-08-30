-- Rechte Schnitt 6, Scheibe 3: Bewerber-RLS auf das Modell (perm_*). Bereich 'bewerber', Tabelle cvs.
-- IST: EINE Policy "HR full access cvs" (ALL) = read+write GLOBAL für alle 5 internen Rollen
-- (management/hr/finance/projektleiter/teamlead). Kein self, keine Projektgrenze. Showcase läuft separat (Token).
--
-- WICHTIG (User 2026-08-30): Leads-Seed zurück auf 'all'. Schnitt 5 hatte ihn auf 'own' verengt, weil die KI
-- (ai_scoped cvs) 'own' war — aber die Basis-App-RLS ist global, und entschieden ist: ALLE Leads sehen ALLE
-- Bewerber. 'own' scharf zu schalten wäre eine ÄNDERUNG (Ylli sähe nur noch seine), keine Nachbildung.
-- Nebenwirkung gewollt: die KI zieht auf 'all' mit → der alte KI-vs-App-Widerspruch verschwindet.
-- Finance read->edit: IST gibt Finance volles ALL (read+write) auf cvs; Seed stand auf read (unter-granted). 0 Nutzer.

begin;

update public.role_permissions set projects='all'
  where area_key='bewerber' and role_key in ('projektleiter','teamlead');
update public.role_permissions set mode='edit'
  where area_key='bewerber' and role_key='finance';

drop policy if exists "HR full access cvs" on public.cvs;

create policy cvs_perm_select on public.cvs for select to authenticated
using ( public.perm_mode(auth.uid(),'bewerber') <> 'none'
        and public.perm_proj_ok(auth.uid(),'bewerber', project_id, null) );

create policy cvs_perm_insert on public.cvs for insert to authenticated
with check ( public.perm_mode(auth.uid(),'bewerber') = 'edit'
             and public.perm_proj_ok(auth.uid(),'bewerber', project_id, null) );

create policy cvs_perm_update on public.cvs for update to authenticated
using ( public.perm_mode(auth.uid(),'bewerber') = 'edit'
        and public.perm_proj_ok(auth.uid(),'bewerber', project_id, null) )
with check ( public.perm_mode(auth.uid(),'bewerber') = 'edit'
             and public.perm_proj_ok(auth.uid(),'bewerber', project_id, null) );

create policy cvs_perm_delete on public.cvs for delete to authenticated
using ( public.perm_mode(auth.uid(),'bewerber') = 'edit'
        and public.perm_proj_ok(auth.uid(),'bewerber', project_id, null) );

commit;

-- ── ROLLBACK (manuell) ──
-- update public.role_permissions set projects='own' where area_key='bewerber' and role_key in ('projektleiter','teamlead');
-- update public.role_permissions set mode='read' where area_key='bewerber' and role_key='finance';
-- drop policy if exists cvs_perm_select on public.cvs;
-- drop policy if exists cvs_perm_insert on public.cvs;
-- drop policy if exists cvs_perm_update on public.cvs;
-- drop policy if exists cvs_perm_delete on public.cvs;
-- create policy "HR full access cvs" on public.cvs for all to authenticated
--   using (exists (select 1 from app_users where user_id=auth.uid() and role_keys && array['management','hr','finance','projektleiter','teamlead']::text[]))
--   with check (exists (select 1 from app_users where user_id=auth.uid() and role_keys && array['management','hr','finance','projektleiter','teamlead']::text[]));
