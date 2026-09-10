-- Reisewelt-Demo: Organigramm (org_nodes) für proj_rw_demo. Behebt „Organigramm geht nicht" (keine Hierarchie).
-- Struktur: Teamleitung (Besart Hoxha, 011) → Qualität & Back-Office (Dafina Leka, 012) + Agenten Reise (001-010).
delete from public.org_nodes where project_id='proj_rw_demo';
insert into public.org_nodes (id, project_id, parent_id, title, subtitle, color, skill, employees, seq, auto_built) values
 ('e1000000-0000-4000-8000-000000000001','proj_rw_demo',null,'Teamleitung','Reisewelt','#0F5661','reise',
    '["a0000000-0000-4000-8000-000000000011"]'::jsonb, 0, false),
 ('e1000000-0000-4000-8000-000000000002','proj_rw_demo','e1000000-0000-4000-8000-000000000001','Qualität & Back-Office',null,'#7c3aed','reise',
    '["a0000000-0000-4000-8000-000000000012"]'::jsonb, 1, false),
 ('e1000000-0000-4000-8000-000000000003','proj_rw_demo','e1000000-0000-4000-8000-000000000001','Agenten Reise','Reiseberatung & Buchung','#0ea5b7','reise',
    '["a0000000-0000-4000-8000-000000000001","a0000000-0000-4000-8000-000000000002","a0000000-0000-4000-8000-000000000003","a0000000-0000-4000-8000-000000000004","a0000000-0000-4000-8000-000000000005","a0000000-0000-4000-8000-000000000006","a0000000-0000-4000-8000-000000000007","a0000000-0000-4000-8000-000000000008","a0000000-0000-4000-8000-000000000009","a0000000-0000-4000-8000-000000000010"]'::jsonb, 2, false);
