-- Jobmesse-Versand unregelmäßig statt fester Takt (Zustellbarkeit neues Postfach): der Dispatcher läuft
-- minütlich, feuert aber nur, wenn next_send_at erreicht ist, mit zufälligem Abstand + schwankender Batch-Größe.
insert into public.app_config(key,value) values ('jsr_jobfair_pace_v1', jsonb_build_object(
  'gap_min_minutes', 6, 'gap_max_minutes', 14,   -- Abstand zufällig 6-14 Min
  'batch_min', 15, 'batch_max', 30,              -- Anzahl je Lauf zufällig 15-30
  'hour_start', 8, 'hour_end', 21,               -- Tagesfenster (Europe/Berlin), kein Nachtversand
  'timezone', 'Europe/Berlin'
)) on conflict (key) do update set value=excluded.value;
insert into public.app_config(key,value) values ('jsr_jobfair_pace_state_v1', jsonb_build_object('next_send_at', null))
  on conflict (key) do nothing;
