-- Kalender-Erinnerung: 15 Minuten vor jedem Termin eine Nachricht (Mail + Slack) an alle Teilnehmer.
-- Jeder kann sie für sich abschalten (calendar_reminder_prefs). Doppelversand ausgeschlossen: Anspruch wird VOR dem
-- Senden geschrieben (calendar_reminders_sent, Unique je Termin+Tag+Person) — Muster aus dem Dispatcher-Rennen.
create table if not exists public.calendar_reminder_prefs (
  employee_id uuid primary key references public.employees(id) on delete cascade,
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);
create table if not exists public.calendar_reminders_sent (
  event_id uuid not null,
  occurrence_date date not null,
  employee_id uuid not null,
  sent_at timestamptz not null default now(),
  channel text,
  primary key (event_id, occurrence_date, employee_id)
);
alter table public.calendar_reminder_prefs enable row level security;
alter table public.calendar_reminders_sent enable row level security;
-- Eigene Einstellung lesen und setzen (Mitarbeiter über get_my_employee_id), intern lesen alle Back-Office-Zugänge.
drop policy if exists calrem_prefs_self on public.calendar_reminder_prefs;
create policy calrem_prefs_self on public.calendar_reminder_prefs for all to authenticated
  using (employee_id = public.get_my_employee_id()) with check (employee_id = public.get_my_employee_id());
drop policy if exists calrem_sent_internal on public.calendar_reminders_sent;
create policy calrem_sent_internal on public.calendar_reminders_sent for select to authenticated
  using (employee_id = public.get_my_employee_id());
