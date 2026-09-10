-- Reisewelt-Demo: Beispiel-Wochenberichte (presentations). ReportsView listet sie, praesentation.html rendert.
-- Der Deck-Motor (shared/presentation-slides.js) ist call-center-KPI-spezifisch; ohne _skills rendert er sauber
-- eine gebrandete Titel- + Abschlussfolie (kein leeres KPI-Gerüst). Reicht als Beispiel-Bericht für die Demo.
delete from public.presentations where project_id='proj_rw_demo';
insert into public.presentations (id, project_id, skill, period_type, period_year, period_no, title, data, public_token, published, kind) values
 ('f1000000-0000-4000-8000-000000000037','proj_rw_demo',null,'kw',2026,37,'Wochenbericht KW 37 · Reisewelt',
   '{"_theme":{"projName":"Reisewelt","accent":"#0F5661"},"titel":{"untertitel":"Wochenbericht"}}'::jsonb,
   'reisewelt-demo-kw37', true, 'weekly'),
 ('f1000000-0000-4000-8000-000000000036','proj_rw_demo',null,'kw',2026,36,'Wochenbericht KW 36 · Reisewelt',
   '{"_theme":{"projName":"Reisewelt","accent":"#0F5661"},"titel":{"untertitel":"Wochenbericht"}}'::jsonb,
   'reisewelt-demo-kw36', true, 'weekly');
