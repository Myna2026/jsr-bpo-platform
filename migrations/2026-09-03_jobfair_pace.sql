-- Jobmesse-Versand unregelmäßig statt fester Takt (Zustellbarkeit neues Postfach): der Dispatcher läuft
-- minütlich, feuert aber nur, wenn next_send_at erreicht ist, mit zufälligem Abstand + schwankender Batch-Größe.
-- Werte auf sanftes Aufwärmen gesetzt, nachdem Zoho das neue Postfach wegen "unusual sending activity"
-- gedrosselt hat (der Dispatcher regelt zusätzlich selbst nach: bei Abweisungen längere Pause + kleinerer Batch).
insert into public.app_config(key,value) values ('jsr_jobfair_pace_v1', jsonb_build_object(
  'gap_min_minutes', 10, 'gap_max_minutes', 18,  -- Abstand zufällig 10-18 Min
  'batch_min', 2, 'batch_max', 4,                -- kleine Häppchen (Aufwärmen)
  'hour_start', 8, 'hour_end', 21,               -- Tagesfenster (Europe/Berlin), kein Nachtversand
  'timezone', 'Europe/Berlin'
)) on conflict (key) do update set value=excluded.value;
insert into public.app_config(key,value) values ('jsr_jobfair_pace_state_v1', jsonb_build_object('next_send_at', null))
  on conflict (key) do nothing;
