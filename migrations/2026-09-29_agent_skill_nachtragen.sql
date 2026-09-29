-- Elf Agenten hatten ein Projekt, aber keinen project_skill. Bei Agenten sind die flachen Felder
-- project_id/project_skill die Zuordnung (project_assignments bleibt bei ihnen bewusst leer, siehe
-- docs/fachmodell/personen-und-datenmodell.md). Ein leerer Skill faellt damit aus jeder Auswertung
-- heraus, die je Projekt UND Skill rechnet.
--
-- Nachgetragen wird nur, was belegbar ist: aus der bestaetigten Schulungsklasse (training_plans.
-- confirmed_ids), bei zweien zusaetzlich durch Schichten im selben Skill gestuetzt.
-- Drei Faelle bleiben offen, weil es keine Quelle gibt: Dhurata Kastrati (gekuendigt, keine Schulung,
-- keine Schicht), Arben Kelmendi und Valon Gashi (beide Status "contract", noch keiner Klasse
-- zugeordnet). Die gehoeren von Hand gesetzt, sobald die Klasse feststeht.
update public.employees e
   set project_skill = v.skill
  from (values
    ('Ardit',    'Zeqiri',    'proj_gn_e5f6a7b8', '1st_level'),   -- Klasse "1Level", dazu 1 Schicht 1st_level
    ('Denis',    'Haziri',    'proj_gn_e5f6a7b8', '1st_level'),   -- Klasse "1Level", dazu 5 Schichten 1st_level
    ('Arta',     'Rexha',     'proj_gn_e5f6a7b8', 'retention'),   -- Klasse "Giga Retention"
    ('Dibran',   'Krasniqi',  'proj_gn_e5f6a7b8', 'retention'),
    ('Enesa',    'Palloshi',  'proj_gn_e5f6a7b8', 'retention'),
    ('Haris',    'Ajvazi',    'proj_gn_e5f6a7b8', 'retention'),
    ('Visar',    'Thaqi',     'proj_gn_e5f6a7b8', 'retention'),
    ('Hazir',    'Hakiqi',    'proj_hc_a1b2c3d4', 'sales')        -- Klasse "HC Sales"
  ) as v(vn, nn, pid, skill)
 where e.first_name = v.vn and e.last_name = v.nn and e.project_id = v.pid
   and e.position = 'Agent' and coalesce(nullif(e.project_skill,''),'') = '';
