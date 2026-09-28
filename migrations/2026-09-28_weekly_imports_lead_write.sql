-- Rohdateien der Datenimporte: Projektleiter duerfen ihr eigenes Projekt archivieren.
--
-- Befund 2026-09-28: Die Tabelle data_imports wurde beim Projektleiter-Umbau auf
--   is_management() OR (is_planner() AND project_id = get_my_employee_project_id())
-- erweitert, die Storage-Policy fuer den Bucket weekly-imports aber nicht. Seit dem
-- 27.08.2026 (Umstellung von Edi Shaqiri auf die Rolle projektleiter) lief jeder seiner
-- Uploads durch, WAEHREND die Rohdatei still verworfen wurde: 139 Importe ohne Archiv.
--
-- Additiv: die bestehende Policy "weekly_imports mgmt" bleibt unveraendert, hier kommt
-- nur eine zweite dazu. Policies werden ODER-verknuepft. Der erste Pfadteil ist die
-- Projekt-ID (z. B. proj_hc_a1b2c3d4/forecast_sales/...), genau wie in data_imports.
create policy "weekly_imports lead own project" on storage.objects
  for all
  using (
    bucket_id = 'weekly-imports'
    and public.is_planner()
    and (storage.foldername(name))[1] = public.get_my_employee_project_id()
  )
  with check (
    bucket_id = 'weekly-imports'
    and public.is_planner()
    and (storage.foldername(name))[1] = public.get_my_employee_project_id()
  );
