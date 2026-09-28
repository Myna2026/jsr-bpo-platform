-- Versand-Sperre für den CPO-Report und Annas Wächter.
-- Der Cron läuft alle fünf Minuten und die Function entscheidet selbst, ob ihr Zeitfenster dran ist
-- (so bleibt die Uhrzeit auch über die Zeitumstellung richtig). Damit dabei nichts doppelt rausgeht,
-- wird der Anspruch VOR dem Senden geschrieben: der Primärschlüssel lässt einen zweiten Versuch
-- für denselben Tag und dasselbe Fenster auflaufen (siehe Falle „Dispatcher-Rennen").
create table if not exists public.cpo_report_log (
  day        date        not null,
  slot       text        not null,          -- '13' | '19' | 'watch'
  sent_at    timestamptz not null default now(),
  recipients text[],
  note       text,
  primary key (day, slot)
);

alter table public.cpo_report_log enable row level security;

-- Nur Management darf mitlesen; geschrieben wird ausschliesslich von der Function (service role).
drop policy if exists "cpo_report_log read mgmt" on public.cpo_report_log;
create policy "cpo_report_log read mgmt" on public.cpo_report_log
  for select using (public.is_management());
