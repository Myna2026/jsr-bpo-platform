-- Newbie-Grenze stand auf 88 Wochen: dadurch war im Wochenbericht JEDER Mitarbeiter als NEU
-- markiert, auch wer seit anderthalb Jahren da ist. Zurueck auf acht Wochen.
-- Das Eingabefeld im Leitstand ist jetzt zusaetzlich auf 52 Wochen gedeckelt.
update public.app_config set value = '8'::jsonb where key = 'jsr_report_newbie_weeks';
select key, value from public.app_config where key='jsr_report_newbie_weeks';
