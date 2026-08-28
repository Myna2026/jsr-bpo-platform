-- Zentrale Zeitsteuerung der Agenten-Erinnerungen. Ein Ort für „wann geht was raus", statt fester Cron-Zeiten.
-- Eine GLOBAL-Zeile je Erinnerung (user_id NULL) + optionale Über­schreibung je Person (user_id gesetzt).
-- Die Functions lesen das; die Crons feuern nur noch STÜNDLICH, die Function entscheidet nach dieser Tabelle.
-- Zeiten in BERLIN-Stunden. weekend-Regel bleibt hart (nie Sa/So). Management editiert in der Übersicht.
create table if not exists public.reminder_schedule (
  reminder_key text not null,
  user_id      uuid,                       -- NULL = global; gesetzt = Über­schreibung für diese Person
  active       boolean not null default true,
  hours        int[]  not null default '{8}',       -- Berlin-Stunden, zu denen gefeuert wird (mehrere möglich)
  cadence      text   not null default 'daily',     -- daily | weekly | every_2_days | monthly | twice_monthly
  weekday      int,                                  -- für weekly: 1=Mo … 7=So
  month_days   int[],                                -- für monthly/twice_monthly: z. B. {1,15} oder {3,4,5,6,7,8,9}
  updated_at   timestamptz default now()
);
create unique index if not exists reminder_schedule_global on public.reminder_schedule(reminder_key) where user_id is null;
create unique index if not exists reminder_schedule_person on public.reminder_schedule(reminder_key, user_id) where user_id is not null;
alter table public.reminder_schedule enable row level security;
drop policy if exists rs_read on public.reminder_schedule;
create policy rs_read on public.reminder_schedule for select using (public.is_management());
drop policy if exists rs_write on public.reminder_schedule;
create policy rs_write on public.reminder_schedule for all using (public.is_management()) with check (public.is_management());
grant select on public.reminder_schedule to service_role;

-- Seed der Global-Zeilen — EXAKT wie die heutigen Crons (Berlin-Zeit), damit sich ohne Eingriff nichts ändert.
insert into public.reminder_schedule(reminder_key, hours, cadence, weekday, month_days) values
  ('clara_digest',    '{7}',        'daily',         null, null),
  ('maya_weekly',     '{9}',        'weekly',        5,    null),
  ('task_reminders',  '{9,12,16}',  'daily',         null, null),
  ('edi_upload',      '{8}',        'every_2_days',  null, null),
  ('fx_rate',         '{8}',        'monthly',       null, '{3,4,5,6,7,8,9}'),
  ('contract_expiry', '{8}',        'twice_monthly', null, '{1,2,3,15,16,17}'),
  ('leader_nudges',   '{8}',        'daily',         null, null)
on conflict do nothing;
