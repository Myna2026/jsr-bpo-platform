-- Reisewelt-Demo: 12 Mitarbeiter auf 4 Skills verteilen (Support/Sales/Bucher/Backoffice) + skillgerechte KPIs.
-- Sales 001-003 · Support 004-006 · Bucher 007-009 · Backoffice 010-012. Nur auf Myna.

-- ── 1) Skill-Verteilung ──────────────────────────────────────────────────────
update public.employees set skill='Sales',      project_skill='Sales',      primary_skill='Sales'      where id in ('a0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000003');
update public.employees set skill='Support',    project_skill='Support',    primary_skill='Support'    where id in ('a0000000-0000-4000-8000-000000000004','a0000000-0000-4000-8000-000000000005','a0000000-0000-4000-8000-000000000006');
update public.employees set skill='Bucher',     project_skill='Bucher',     primary_skill='Bucher'     where id in ('a0000000-0000-4000-8000-000000000007','a0000000-0000-4000-8000-000000000008','a0000000-0000-4000-8000-000000000009');
update public.employees set skill='Backoffice', project_skill='Backoffice', primary_skill='Backoffice' where id in ('a0000000-0000-4000-8000-000000000010','a0000000-0000-4000-8000-000000000011','a0000000-0000-4000-8000-000000000012');

-- ── 2) KPI-Konfiguration je Skill (thresholds: sehr gut/gut/ausbaufähig/kritisch) ──
delete from public.kpi_entries where kpi_id in (select id from public.kpi_config where project_id='proj_rw_demo');
delete from public.kpi_config where project_id='proj_rw_demo';

insert into public.kpi_config (id, project_id, skill, name, type, unit, level, is_primary, thresholds) values
-- Sales: Conversion (↑), Umsatz/Buchung (↑), AHT (↓)
('kpi_sa_conv','proj_rw_demo','Sales','Conversion','percent','%','agent',true,
 '[{"label":"Sehr gut","min":50,"max":100,"color":"#229701","bg":"#22970122","icon":"🌟"},{"label":"Gut","min":42,"max":49.9,"color":"#4bd910","bg":"#4bd91022","icon":""},{"label":"Ausbaufähig","min":35,"max":41.9,"color":"#edd168","bg":"#edd16822","icon":""},{"label":"Kritisch","min":0,"max":34.9,"color":"#f9051e","bg":"#f9051e22","icon":""}]'::jsonb),
('kpi_sa_rev','proj_rw_demo','Sales','Umsatz / Buchung','number','€','agent',false,
 '[{"label":"Sehr gut","min":1200,"max":100000,"color":"#229701","bg":"#22970122","icon":"🌟"},{"label":"Gut","min":950,"max":1199.9,"color":"#4bd910","bg":"#4bd91022","icon":""},{"label":"Ausbaufähig","min":800,"max":949.9,"color":"#edd168","bg":"#edd16822","icon":""},{"label":"Kritisch","min":0,"max":799.9,"color":"#f9051e","bg":"#f9051e22","icon":""}]'::jsonb),
('kpi_sa_aht','proj_rw_demo','Sales','AHT','minutes','min','agent',false,
 '[{"label":"Sehr gut","min":0,"max":7,"color":"#229701","bg":"#22970122","icon":"🌟"},{"label":"Gut","min":7.01,"max":8,"color":"#4bd910","bg":"#4bd91022","icon":""},{"label":"Ausbaufähig","min":8.01,"max":9,"color":"#edd168","bg":"#edd16822","icon":""},{"label":"Kritisch","min":9.01,"max":100,"color":"#f9051e","bg":"#f9051e22","icon":""}]'::jsonb),
-- Support: CSAT (↑), AHT (↓), Lösungsquote (↑)
('kpi_su_csat','proj_rw_demo','Support','CSAT','percent','%','agent',true,
 '[{"label":"Sehr gut","min":90,"max":100,"color":"#229701","bg":"#22970122","icon":"🌟"},{"label":"Gut","min":82,"max":89.9,"color":"#4bd910","bg":"#4bd91022","icon":""},{"label":"Ausbaufähig","min":75,"max":81.9,"color":"#edd168","bg":"#edd16822","icon":""},{"label":"Kritisch","min":0,"max":74.9,"color":"#f9051e","bg":"#f9051e22","icon":""}]'::jsonb),
('kpi_su_aht','proj_rw_demo','Support','AHT','minutes','min','agent',false,
 '[{"label":"Sehr gut","min":0,"max":5,"color":"#229701","bg":"#22970122","icon":"🌟"},{"label":"Gut","min":5.01,"max":6.5,"color":"#4bd910","bg":"#4bd91022","icon":""},{"label":"Ausbaufähig","min":6.51,"max":8,"color":"#edd168","bg":"#edd16822","icon":""},{"label":"Kritisch","min":8.01,"max":100,"color":"#f9051e","bg":"#f9051e22","icon":""}]'::jsonb),
('kpi_su_fcr','proj_rw_demo','Support','Lösungsquote','percent','%','agent',false,
 '[{"label":"Sehr gut","min":88,"max":100,"color":"#229701","bg":"#22970122","icon":"🌟"},{"label":"Gut","min":80,"max":87.9,"color":"#4bd910","bg":"#4bd91022","icon":""},{"label":"Ausbaufähig","min":72,"max":79.9,"color":"#edd168","bg":"#edd16822","icon":""},{"label":"Kritisch","min":0,"max":71.9,"color":"#f9051e","bg":"#f9051e22","icon":""}]'::jsonb),
-- Bucher: Buchungen/Tag (↑), Fehlerquote (↓), Bearbeitungszeit (↓)
('kpi_bu_cnt','proj_rw_demo','Bucher','Buchungen / Tag','number','','agent',true,
 '[{"label":"Sehr gut","min":36,"max":1000,"color":"#229701","bg":"#22970122","icon":"🌟"},{"label":"Gut","min":30,"max":35.9,"color":"#4bd910","bg":"#4bd91022","icon":""},{"label":"Ausbaufähig","min":24,"max":29.9,"color":"#edd168","bg":"#edd16822","icon":""},{"label":"Kritisch","min":0,"max":23.9,"color":"#f9051e","bg":"#f9051e22","icon":""}]'::jsonb),
('kpi_bu_err','proj_rw_demo','Bucher','Fehlerquote','percent','%','agent',false,
 '[{"label":"Sehr gut","min":0,"max":2,"color":"#229701","bg":"#22970122","icon":"🌟"},{"label":"Gut","min":2.01,"max":3.5,"color":"#4bd910","bg":"#4bd91022","icon":""},{"label":"Ausbaufähig","min":3.51,"max":5,"color":"#edd168","bg":"#edd16822","icon":""},{"label":"Kritisch","min":5.01,"max":100,"color":"#f9051e","bg":"#f9051e22","icon":""}]'::jsonb),
('kpi_bu_time','proj_rw_demo','Bucher','Bearbeitungszeit','minutes','min','agent',false,
 '[{"label":"Sehr gut","min":0,"max":9,"color":"#229701","bg":"#22970122","icon":"🌟"},{"label":"Gut","min":9.01,"max":10.5,"color":"#4bd910","bg":"#4bd91022","icon":""},{"label":"Ausbaufähig","min":10.51,"max":12,"color":"#edd168","bg":"#edd16822","icon":""},{"label":"Kritisch","min":12.01,"max":100,"color":"#f9051e","bg":"#f9051e22","icon":""}]'::jsonb),
-- Backoffice: Vorgänge/Tag (↑), Durchlaufzeit Std (↓), Rückläuferquote (↓)
('kpi_bo_cnt','proj_rw_demo','Backoffice','Vorgänge / Tag','number','','agent',true,
 '[{"label":"Sehr gut","min":44,"max":1000,"color":"#229701","bg":"#22970122","icon":"🌟"},{"label":"Gut","min":38,"max":43.9,"color":"#4bd910","bg":"#4bd91022","icon":""},{"label":"Ausbaufähig","min":32,"max":37.9,"color":"#edd168","bg":"#edd16822","icon":""},{"label":"Kritisch","min":0,"max":31.9,"color":"#f9051e","bg":"#f9051e22","icon":""}]'::jsonb),
('kpi_bo_time','proj_rw_demo','Backoffice','Durchlaufzeit','number','Std','agent',false,
 '[{"label":"Sehr gut","min":0,"max":3,"color":"#229701","bg":"#22970122","icon":"🌟"},{"label":"Gut","min":3.01,"max":4,"color":"#4bd910","bg":"#4bd91022","icon":""},{"label":"Ausbaufähig","min":4.01,"max":5,"color":"#edd168","bg":"#edd16822","icon":""},{"label":"Kritisch","min":5.01,"max":100,"color":"#f9051e","bg":"#f9051e22","icon":""}]'::jsonb),
('kpi_bo_ret','proj_rw_demo','Backoffice','Rückläuferquote','percent','%','agent',false,
 '[{"label":"Sehr gut","min":0,"max":4,"color":"#229701","bg":"#22970122","icon":"🌟"},{"label":"Gut","min":4.01,"max":6,"color":"#4bd910","bg":"#4bd91022","icon":""},{"label":"Ausbaufähig","min":6.01,"max":8,"color":"#edd168","bg":"#edd16822","icon":""},{"label":"Kritisch","min":8.01,"max":100,"color":"#f9051e","bg":"#f9051e22","icon":""}]'::jsonb);

-- ── 3) KPI-Werte je MA (5 Wochen KW33-37, base@KW35 + Trend/Woche; gut/schwach gestreut) ──
insert into public.kpi_entries (emp_id, kw, year, kpi_id, value)
select emp::uuid, kw, 2026, kpi, round((base + (kw-35)*trend)::numeric, 1)
from (values
  -- Sales (conv/rev/aht)
  ('a0000000-0000-4000-8000-000000000001','kpi_sa_conv',54,0.6),('a0000000-0000-4000-8000-000000000001','kpi_sa_rev',1320,12),('a0000000-0000-4000-8000-000000000001','kpi_sa_aht',7.0,-0.05),
  ('a0000000-0000-4000-8000-000000000002','kpi_sa_conv',46,0.3),('a0000000-0000-4000-8000-000000000002','kpi_sa_rev',985,8),('a0000000-0000-4000-8000-000000000002','kpi_sa_aht',8.1,-0.03),
  ('a0000000-0000-4000-8000-000000000003','kpi_sa_conv',37,-0.4),('a0000000-0000-4000-8000-000000000003','kpi_sa_rev',820,-6),('a0000000-0000-4000-8000-000000000003','kpi_sa_aht',9.2,0.06),
  -- Support (csat/aht/fcr)
  ('a0000000-0000-4000-8000-000000000004','kpi_su_csat',93,0.4),('a0000000-0000-4000-8000-000000000004','kpi_su_aht',4.8,-0.04),('a0000000-0000-4000-8000-000000000004','kpi_su_fcr',90,0.3),
  ('a0000000-0000-4000-8000-000000000005','kpi_su_csat',85,0.2),('a0000000-0000-4000-8000-000000000005','kpi_su_aht',6.2,-0.02),('a0000000-0000-4000-8000-000000000005','kpi_su_fcr',83,0.2),
  ('a0000000-0000-4000-8000-000000000006','kpi_su_csat',77,-0.3),('a0000000-0000-4000-8000-000000000006','kpi_su_aht',7.9,0.05),('a0000000-0000-4000-8000-000000000006','kpi_su_fcr',73,-0.4),
  -- Bucher (buchungen/fehler/zeit)
  ('a0000000-0000-4000-8000-000000000007','kpi_bu_cnt',38,0.5),('a0000000-0000-4000-8000-000000000007','kpi_bu_err',1.5,-0.05),('a0000000-0000-4000-8000-000000000007','kpi_bu_time',8.6,-0.06),
  ('a0000000-0000-4000-8000-000000000008','kpi_bu_cnt',30,0.3),('a0000000-0000-4000-8000-000000000008','kpi_bu_err',3.2,-0.04),('a0000000-0000-4000-8000-000000000008','kpi_bu_time',10.1,-0.03),
  ('a0000000-0000-4000-8000-000000000009','kpi_bu_cnt',24,-0.4),('a0000000-0000-4000-8000-000000000009','kpi_bu_err',5.2,0.08),('a0000000-0000-4000-8000-000000000009','kpi_bu_time',11.8,0.07),
  -- Backoffice (vorgänge/durchlauf/rückläufer)
  ('a0000000-0000-4000-8000-000000000010','kpi_bo_cnt',46,0.6),('a0000000-0000-4000-8000-000000000010','kpi_bo_time',2.5,-0.04),('a0000000-0000-4000-8000-000000000010','kpi_bo_ret',3.5,-0.06),
  ('a0000000-0000-4000-8000-000000000011','kpi_bo_cnt',40,0.3),('a0000000-0000-4000-8000-000000000011','kpi_bo_time',3.5,-0.03),('a0000000-0000-4000-8000-000000000011','kpi_bo_ret',5.0,-0.04),
  ('a0000000-0000-4000-8000-000000000012','kpi_bo_cnt',34,0.2),('a0000000-0000-4000-8000-000000000012','kpi_bo_time',4.8,0.04),('a0000000-0000-4000-8000-000000000012','kpi_bo_ret',7.2,0.06)
) ek(emp,kpi,base,trend)
cross join (values (33),(34),(35),(36),(37)) w(kw);

-- ── 4) Skill an Schichten/Calls/Org angleichen ───────────────────────────────
update public.shift_assignments s set skill=e.project_skill from public.employees e where e.id=s.employee_id and s.project_id='proj_rw_demo';
update public.shift_checkins    s set skill=e.project_skill from public.employees e where e.id=s.employee_id and s.project_id='proj_rw_demo';
update public.call_samples      s set skill=e.project_skill from public.employees e where e.id=s.employee_id and s.project_id='proj_rw_demo';

-- ── 5) Organigramm nach Skill-Teams umbauen ──────────────────────────────────
delete from public.org_nodes where project_id='proj_rw_demo';
insert into public.org_nodes (id, project_id, parent_id, title, subtitle, color, skill, employees, seq, auto_built) values
 ('e1000000-0000-4000-8000-000000000001','proj_rw_demo',null,'Teamleitung','Reisewelt','#0F5661',null,'["a0000000-0000-4000-8000-000000000011"]'::jsonb,0,false),
 ('e1000000-0000-4000-8000-000000000010','proj_rw_demo','e1000000-0000-4000-8000-000000000001','Sales','Verkauf & Upselling','#16a34a','Sales','["a0000000-0000-4000-8000-000000000001","a0000000-0000-4000-8000-000000000002","a0000000-0000-4000-8000-000000000003"]'::jsonb,1,false),
 ('e1000000-0000-4000-8000-000000000011','proj_rw_demo','e1000000-0000-4000-8000-000000000001','Support','Kundenbetreuung','#0ea5b7','Support','["a0000000-0000-4000-8000-000000000004","a0000000-0000-4000-8000-000000000005","a0000000-0000-4000-8000-000000000006"]'::jsonb,2,false),
 ('e1000000-0000-4000-8000-000000000012','proj_rw_demo','e1000000-0000-4000-8000-000000000001','Bucher','Buchungsabwicklung','#6366f1','Bucher','["a0000000-0000-4000-8000-000000000007","a0000000-0000-4000-8000-000000000008","a0000000-0000-4000-8000-000000000009"]'::jsonb,3,false),
 ('e1000000-0000-4000-8000-000000000013','proj_rw_demo','e1000000-0000-4000-8000-000000000001','Backoffice','Verwaltung & Reklamation','#d97706','Backoffice','["a0000000-0000-4000-8000-000000000010","a0000000-0000-4000-8000-000000000012"]'::jsonb,4,false);
