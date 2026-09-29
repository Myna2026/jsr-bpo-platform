-- Spalte "Handle" aus dem Auftraggeber-Export mitfuehren: die Zahl der bearbeiteten Gespraeche.
-- Sie ist bei Agenten mit Outbound-Taetigkeit gefuellt, waehrend "Answered" leer bleibt — genau die
-- Leute, die bisher ohne Zahlen im Bericht standen. Abgerechnet und berichtet wird weiter Answered
-- (Vorgabe Eigentuemer 2026-09-29), Handle steht zur Einordnung daneben.
alter table public.weekly_calls add column if not exists handled integer;
comment on column public.weekly_calls.handled is
  'Spalte "Handle" aus dem Genesys-Export: bearbeitete Gespraeche inkl. Outbound. Bericht zeigt Answered, Handle nur zur Einordnung.';

select column_name from information_schema.columns
 where table_schema='public' and table_name='weekly_calls' and column_name in ('answered','handled','outbound');
