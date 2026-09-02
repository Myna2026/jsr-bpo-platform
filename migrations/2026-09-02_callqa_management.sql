-- Call-Qualität als eigener Rechtebereich (callqa) wurde für qm angelegt, aber Management fehlte die Zeile →
-- perm() fällt auf visible=false zurück, darum fehlte der Menüpunkt „Call-Qualität" bei Management. Management
-- soll alles sehen. Additiv, idempotent.
insert into public.role_permissions(role_key,area_key,visible,mode,projects) values
  ('management','callqa',true,'edit','all')
  on conflict (role_key,area_key) do update set visible=true, mode='edit', projects=excluded.projects;
