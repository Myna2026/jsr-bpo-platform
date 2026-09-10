-- Arbeitsplan zum Projektwerkzeug: 5 Zustände (Fortschritt leitet sich daraus ab, keine getippten Zahlen) +
-- Beginn-Datum für die Balken (Gantt spannt start_date → due_date).
-- Zustände: offen · in_arbeit · pausiert · wartet · erledigt. Fortschritt (Frontend): 0 / 50 / 50 / 50 / 100,
-- Hauptpunkt = Mittel der Unterpunkte. Die progress-Spalte wird beim Zustandswechsel synchron gehalten.

alter table public.improvement_items add column if not exists start_date date;

-- Alte Werte auf die neue Sprache heben (Reihenfolge: erst Constraint weg, dann umschreiben, dann neu).
alter table public.improvement_items drop constraint if exists improvement_items_status_check;
update public.improvement_items set status='in_arbeit' where status='laeuft';
update public.improvement_items set status='pausiert'  where status='zurueckgestellt';
alter table public.improvement_items
  add constraint improvement_items_status_check check (status in ('offen','in_arbeit','pausiert','wartet','erledigt'));
