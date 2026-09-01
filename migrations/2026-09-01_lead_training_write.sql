-- Führung (projektleiter/teamlead) pflegt Schulungen des EIGENEN Projekts (Plan + Teilnehmer confirmed_ids).
-- Menü kommt über LEAD_ALLOWED_TABS (Frontend). Schreibrecht: schulung=edit je eigenem Projekt + projektbezogene
-- Policy auf training_plans, neben der bestehenden management/hr/finance-Policy. Lesen konnten sie schon.
insert into public.role_permissions(role_key,area_key,visible,mode,projects) values
  ('projektleiter','schulung',true,'edit','own'),
  ('teamlead','schulung',true,'edit','own')
  on conflict (role_key,area_key) do update set visible=excluded.visible, mode=excluded.mode, projects=excluded.projects;

drop policy if exists training_plans_planner on public.training_plans;
create policy training_plans_planner on public.training_plans for all
  using (perm_mode(auth.uid(),'schulung')='edit' and perm_proj_ok(auth.uid(),'schulung',project_id,NULL))
  with check (perm_mode(auth.uid(),'schulung')='edit' and perm_proj_ok(auth.uid(),'schulung',project_id,NULL));
