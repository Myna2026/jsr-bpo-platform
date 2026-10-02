-- Die Zusage entfaellt. Entscheidung User 2026-10-02: wir sagen nichts zu. Der Ablauf ist Forecast
-- vom Auftraggeber, unsere interne Planung, Lieferung, Rueckmeldung. Drei Groessen, keine vierte.
-- Die beiden Spalten waren wenige Minuten zuvor fuer die zweiteilige Zusage angelegt worden und sind
-- leer; sie werden wieder entfernt. committed bleibt als Altbestand stehen, wird aber nicht mehr
-- geschrieben und nirgends mehr gelesen.
alter table forecast_day drop column if exists committed_main;
alter table forecast_day drop column if exists committed_second;
comment on column forecast_day.committed is 'Altbestand, wird seit 2026-10-02 nicht mehr gepflegt: wir geben keine Zusage ab.';
