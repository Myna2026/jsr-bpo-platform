-- qm + trainer werden Back-Office-Rollen. Weg 2: Call-Qualität als EIGENER Rechte-Bereich (nicht mehr unter kpi),
-- damit qm nur die Call-Bewertung sieht, nicht Performance/Auswertung/Forecast. trainer = ganzer Schulungs-
-- Werkzeugkasten + Mitarbeiter des eigenen Projekts (lesen). Ardita → qm, Armelinda → trainer (Arlinda bleibt).

-- 1. Neuer Rechte-Bereich Call-Qualität; callqa aus kpi herauslösen.
insert into public.permission_areas(key,label,seq,axes,menu_keys) values
  ('callqa','Call-Qualität',16,'{"skill":true,"gehalt":false,"projekt":true,"hierarchie":false}'::jsonb, array['callqa'])
  on conflict (key) do nothing;
update public.permission_areas set menu_keys = array['performance','auswertung','fcist','forecast'] where key='kpi';

-- 2. Bewertungsbögen/Stichproben/Scores: neben is_admin() auch Call-Qualität-Bewerter (perm callqa=edit) zulassen.
drop policy if exists call_criteria_callqa on public.call_criteria;
create policy call_criteria_callqa on public.call_criteria for all
  using (perm_mode(auth.uid(),'callqa')='edit') with check (perm_mode(auth.uid(),'callqa')='edit');
drop policy if exists call_samples_callqa on public.call_samples;
create policy call_samples_callqa on public.call_samples for all
  using (perm_mode(auth.uid(),'callqa')='edit') with check (perm_mode(auth.uid(),'callqa')='edit');
drop policy if exists call_scores_callqa on public.call_scores;
create policy call_scores_callqa on public.call_scores for all
  using (perm_mode(auth.uid(),'callqa')='edit') with check (perm_mode(auth.uid(),'callqa')='edit');

-- 3. Rollenrechte. qm NUR Call-Qualität. trainer Schulung (bearbeiten) + Mitarbeiter (lesen), eigenes Projekt.
insert into public.role_permissions(role_key,area_key,visible,mode,projects) values
  ('qm','callqa',true,'edit','all')
  on conflict (role_key,area_key) do update set visible=excluded.visible, mode=excluded.mode, projects=excluded.projects;
-- qm braucht die Mitarbeiter zum Bewerten (employees_masked verlangt perm_mode('emp')<>'none'). Lesen ja, aber
-- visible=false → KEIN Mitarbeiter-Menü; columns=operativ → keine Gehälter. Im Menü sieht qm weiter nur Call-Qualität.
insert into public.role_permissions(role_key,area_key,visible,mode,projects,columns) values
  ('qm','emp',false,'read','all','operativ')
  on conflict (role_key,area_key) do update set visible=excluded.visible, mode=excluded.mode, projects=excluded.projects, columns=excluded.columns;
insert into public.role_permissions(role_key,area_key,visible,mode,projects,columns) values
  ('trainer','schulung',true,'edit','own','operativ'),
  ('trainer','emp',true,'read','own','operativ')
  on conflict (role_key,area_key) do update set visible=excluded.visible, mode=excluded.mode, projects=excluded.projects, columns=excluded.columns;

-- 4. Rollen setzen.
update public.app_users set role_keys = array['qm']::text[] where user_id='8c66548b-3ddc-4d0b-aa50-179dd0b55a39';   -- Ardita Hysenaj
update public.app_users set role_keys = array['trainer']::text[] where full_name='Armelinda Kepuska';
