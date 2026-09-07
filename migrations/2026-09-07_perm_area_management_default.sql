-- Rechte-Bereiche: Management bekommt jeden Bereich automatisch. Verhindert, dass beim Anlegen eines neuen
-- Bereichs (wie zuletzt Call-Qualität / Wissensspeicher) Management vergessen wird und es erst auffällt,
-- wenn jemand etwas vermisst. Backfill für Bestehendes + Trigger für Neue.

-- ── Backfill: fehlende Management-Zeilen (das RETURNING zeigt die Lücken) ─────
insert into public.role_permissions (role_key, area_key, visible, mode, salary, direction, projects, project_ids, skill, columns)
select 'management', a.key, true, 'edit', 'all', 'up', 'all', '{}'::text[], 'all', 'voll'
  from public.permission_areas a
 where not exists (select 1 from public.role_permissions rp where rp.role_key='management' and rp.area_key=a.key)
returning area_key;

-- ── Trigger: neuer Bereich -> Management automatisch sichtbar+edit ────────────
create or replace function public.perm_area_grant_management()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.role_permissions (role_key, area_key, visible, mode, salary, direction, projects, project_ids, skill, columns)
  values ('management', new.key, true, 'edit', 'all', 'up', 'all', '{}'::text[], 'all', 'voll')
  on conflict (role_key, area_key) do nothing;
  return new;
end $$;
drop trigger if exists perm_area_grant_management_t on public.permission_areas;
create trigger perm_area_grant_management_t after insert on public.permission_areas
  for each row execute function public.perm_area_grant_management();
