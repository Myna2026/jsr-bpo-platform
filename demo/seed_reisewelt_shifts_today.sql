-- Reisewelt-Demo: aktuelle Schichten (Sep 10-12, deckt das Demo-Fenster ab) + Check-ins.
-- Damit im Schichtplan „gerade eingecheckt" (grün) UND „geplant, nicht eingecheckt" sichtbar sind.
-- Die 4-Wochen-Schichten (Sep 14 - Okt 9) bleiben bestehen.

delete from public.shift_checkins    where project_id='proj_rw_demo' and work_date in ('2026-09-10','2026-09-11','2026-09-12');
delete from public.shift_assignments where project_id='proj_rw_demo' and work_date in ('2026-09-10','2026-09-11','2026-09-12');

-- Schichten für die 10 Agenten, 3 Tage, rotierend Früh/Mitte/Spät.
insert into public.shift_assignments (project_id, skill, employee_id, work_date, label, shift_value, shift, net_hours, gross_hours)
select 'proj_rw_demo','reise', emp::uuid, dt, lbl, sv, jsonb_build_object('label',lbl,'shift',sv), 8, 8.5
from (values
  ('a0000000-0000-4000-8000-000000000001','Früh','08:00-16:30'),
  ('a0000000-0000-4000-8000-000000000002','Mitte','09:00-17:30'),
  ('a0000000-0000-4000-8000-000000000003','Spät','13:00-21:30'),
  ('a0000000-0000-4000-8000-000000000004','Früh','08:00-16:30'),
  ('a0000000-0000-4000-8000-000000000005','Mitte','09:00-17:30'),
  ('a0000000-0000-4000-8000-000000000006','Spät','13:00-21:30'),
  ('a0000000-0000-4000-8000-000000000007','Früh','08:00-16:30'),
  ('a0000000-0000-4000-8000-000000000008','Mitte','09:00-17:30'),
  ('a0000000-0000-4000-8000-000000000009','Spät','13:00-21:30'),
  ('a0000000-0000-4000-8000-000000000010','Früh','08:00-16:30')
) ag(emp,lbl,sv)
cross join (values (date '2026-09-10'),(date '2026-09-11'),(date '2026-09-12')) d(dt);

-- Check-ins: 6 präsent (grün) + 1 verspätet; die 3 Spät-Agenten (03/06/09) OHNE Check-in = geplant, nicht eingecheckt.
insert into public.shift_checkins (project_id, skill, employee_id, work_date, status, arrival, source, confirmed_by_name)
select 'proj_rw_demo','reise', emp::uuid, dt, st, arr::time, 'timeclock','Zeiterfassung'
from (values
  ('a0000000-0000-4000-8000-000000000001','present','07:58'),
  ('a0000000-0000-4000-8000-000000000002','present','08:56'),
  ('a0000000-0000-4000-8000-000000000004','present','07:50'),
  ('a0000000-0000-4000-8000-000000000005','present','09:03'),
  ('a0000000-0000-4000-8000-000000000007','present','07:59'),
  ('a0000000-0000-4000-8000-000000000010','present','07:45'),
  ('a0000000-0000-4000-8000-000000000008','late','09:22')
) v(emp,st,arr)
cross join (values (date '2026-09-10'),(date '2026-09-11'),(date '2026-09-12')) d(dt);
