-- Harter Beleg: beim Abhaken einer Tagesaufgabe wird der SITZUNGS-Schreibzähler mitgestempelt.
-- Nicht zeitfensterbasiert (das würde bei Parallelarbeit falsch zuordnen), sondern write-basiert:
--   session_writes = Zahl echter Datenschreibvorgänge (create/update/delete) in DER Sitzung bis zum Abhaken.
--   last_write_at  = Zeitpunkt des letzten echten Schreibvorgangs der Sitzung.
--   session_id     = Heartbeat-Sitzung (verbindet mit user_sessions).
-- Daraus ist belastbar ableitbar: eine Sitzung mit abgehakten Aufgaben, in der session_writes 0 bleibt bzw.
-- zwischen zwei Häkchen nicht steigt, hat nichts an den Daten geändert. Additiv/idempotent.
alter table public.daily_tasks_done add column if not exists session_id     text;
alter table public.daily_tasks_done add column if not exists session_writes  int;
alter table public.daily_tasks_done add column if not exists last_write_at   timestamptz;
