-- =============================================================================
-- Präsentationen: interner Zugriff auf MANAGEMENT verengen (nicht HR)      2026-08-11
-- =============================================================================
-- Wie der KPI-Cockpit-Block: Kennzahlen/Berichte sind Steuerungsgrößen, keine
-- Personalarbeit. is_management() (role_keys && {management}) statt is_admin()
-- (management/hr). Der öffentliche Token-Zugriff (get_public_presentation) bleibt
-- unberührt. Idempotent. Im Supabase SQL-Editor ausführen.
-- Abh.: is_management() existiert (2026-08-05_hr_no_management_data.sql).
-- =============================================================================

drop policy if exists presentation_templates_admin_all on public.presentation_templates;
drop policy if exists presentation_templates_mgmt_all  on public.presentation_templates;
create policy presentation_templates_mgmt_all on public.presentation_templates
  for all to authenticated
  using      (public.is_management())
  with check (public.is_management());

drop policy if exists presentations_admin_all on public.presentations;
drop policy if exists presentations_mgmt_all  on public.presentations;
create policy presentations_mgmt_all on public.presentations
  for all to authenticated
  using      (public.is_management())
  with check (public.is_management());

drop policy if exists "presentation_assets admin write" on storage.objects;
drop policy if exists "presentation_assets mgmt write"  on storage.objects;
create policy "presentation_assets mgmt write" on storage.objects
  for all to authenticated
  using      (bucket_id = 'presentation-assets' and public.is_management())
  with check (bucket_id = 'presentation-assets' and public.is_management());

-- Prüfung: select polname from pg_policy where polrelid='public.presentations'::regclass;  -- presentations_mgmt_all
