-- Wissensspeicher Schnitt 10: Zugang fürs Mitarbeiter-Portal. Die Rolle 'mitarbeiter' bekommt LESERECHT auf den
-- Wissensspeicher, aber nur fürs EIGENE Projekt (projects='own'). Damit sieht ein Condor-Mitarbeiter nur Condor
-- (Carlos), sonst nichts — durchgesetzt über perm('wissen') + perm_proj_ok in kb_retrieve/RLS. Kein Upload/Register
-- (das steuert die Portal-UI; 'read' erlaubt ohnehin kein Schreiben). Additiv, do nothing bei Bestand.
insert into public.role_permissions(role_key,area_key,visible,mode,salary,direction,projects,skill) values
 ('mitarbeiter','wissen',true,'read','none','down','own','all')
on conflict (role_key,area_key) do nothing;
