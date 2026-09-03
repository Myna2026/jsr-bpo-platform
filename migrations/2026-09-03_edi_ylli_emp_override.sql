-- Punkt 2: Edi (HolidayCheck) und Ylli (Giganetz) als gegenseitige Vertretung freischalten.
-- Beide bekommen einen user_permissions-Override auf 'emp': beide Projekte (projects='list'),
-- Bearbeiten (mode='edit'), Gehalt an (salary='all', greift ueber die Peer-Rangregel der
-- fuehrung-View nur fuer Untergebene), Spaltenprofil 'fuehrung' (voll minus Bank minus Ausweis).
-- Management/GF bleiben ueber die Projekt-Achse (kein Projekt) aussen vor.

insert into public.user_permissions (user_id, area_key, visible, mode, salary, direction, projects, project_ids, columns, skill)
values
 ('f8c5fe64-7319-455b-8c3b-ddfc59e7e7fe','emp', true,'edit','all','side','list', array['proj_hc_a1b2c3d4','proj_gn_e5f6a7b8'], 'fuehrung','all'),  -- Edi
 ('312020fc-5857-4591-9a1c-f963700053b1','emp', true,'edit','all','side','list', array['proj_hc_a1b2c3d4','proj_gn_e5f6a7b8'], 'fuehrung','all')   -- Ylli
on conflict (user_id, area_key) do update set
 visible=excluded.visible, mode=excluded.mode, salary=excluded.salary, direction=excluded.direction,
 projects=excluded.projects, project_ids=excluded.project_ids, columns=excluded.columns, skill=excluded.skill;
