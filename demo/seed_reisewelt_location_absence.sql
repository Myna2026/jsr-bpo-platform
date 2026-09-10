-- Reisewelt-Demo: Standort Prishtina + erweiterte Check-ins + Abwesenheiten (krank/Urlaub) + Client-View mit absences.

-- ── 1) Alle MA aus Prishtina ─────────────────────────────────────────────────
update public.employees set location='Prishtina', city='Prishtina' where project_id='proj_rw_demo';

-- ── 2) Check-ins auf weitere Werktage (14.-18.9.) ausdehnen, damit an jedem Demo-Tag Live-Status sichtbar ──
insert into public.shift_checkins (project_id, skill, employee_id, work_date, status, arrival, source, confirmed_by_name)
select 'proj_rw_demo', e.project_skill, v.emp::uuid, d.dt, v.st, v.arr::time, 'timeclock','Zeiterfassung'
from (values
  ('a0000000-0000-4000-8000-000000000001','present','07:58'),
  ('a0000000-0000-4000-8000-000000000002','present','08:56'),
  ('a0000000-0000-4000-8000-000000000004','present','07:50'),
  ('a0000000-0000-4000-8000-000000000005','present','09:03'),
  ('a0000000-0000-4000-8000-000000000007','present','07:59'),
  ('a0000000-0000-4000-8000-000000000010','present','07:45'),
  ('a0000000-0000-4000-8000-000000000008','late','09:22')
) v(emp,st,arr)
join public.employees e on e.id=v.emp::uuid
cross join (values (date '2026-09-14'),(date '2026-09-15'),(date '2026-09-16'),(date '2026-09-17'),(date '2026-09-18')) d(dt)
on conflict (project_id,skill,employee_id,work_date,source) do nothing;

-- ── 3) Abwesenheiten (krank/Urlaub) auf ein paar MA — sichtbar im aktuellen + nächsten Zeitraum ──
--     Emp 06 krank (10.-12.9.), Emp 03 krank (16.-17.9.), Emp 09 Urlaub (15.-19.9.), Emp 05 Urlaub (22.-26.9.).
update public.employees set absences='[{"type":"sick","from":"2026-09-10","to":"2026-09-12","days":3,"paid":true,"approved":true,"note":"Grippe"}]'::jsonb where id='a0000000-0000-4000-8000-000000000006';
update public.employees set absences='[{"type":"sick","from":"2026-09-16","to":"2026-09-17","days":2,"paid":true,"approved":true,"note":""}]'::jsonb where id='a0000000-0000-4000-8000-000000000003';
update public.employees set absences='[{"type":"vacation","from":"2026-09-15","to":"2026-09-19","days":5,"paid":true,"approved":true,"note":"Jahresurlaub"}]'::jsonb where id='a0000000-0000-4000-8000-000000000009';
update public.employees set absences='[{"type":"vacation","from":"2026-09-22","to":"2026-09-26","days":5,"paid":true,"approved":true,"note":""}]'::jsonb where id='a0000000-0000-4000-8000-000000000005';

-- ── 4) employees_client_view um absences erweitern (Kunde sieht Abwesenheiten im Schichtplan) ──
drop view if exists public.employees_client_view;
create view public.employees_client_view
with (security_invoker = false, security_barrier = true) as
select e.id, e.first_name, e.last_name, e.position, e.project_skill as skill, e.city, e.photo_url,
       e.language_level, e.project_id, e.status, e.absences, p.color as project_color
from public.employees e left join public.projects p on p.id = e.project_id
where e.status in ('active','training') and e.project_id = public.get_my_client_project_id();
grant select on public.employees_client_view to authenticated;
