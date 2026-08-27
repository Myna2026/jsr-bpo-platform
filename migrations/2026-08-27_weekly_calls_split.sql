-- Call-CSV-Umbau: zwei Quellen (Gesamt + Inbound). Mengen (Answered/Outbound/Transferred/…) aus der Gesamtdatei,
-- Zeiten (AHT/ACW/Talk/Hold) NUR aus der Inbound-Datei. Damit die zwei Importe in EINE Zeile mergen (statt sich
-- gegenseitig zu ersetzen), braucht es einen Unique-Schlüssel für Upsert. Zusätzlich zwei fehlende Mengen-Spalten.
alter table public.weekly_calls add column if not exists transferred int;
alter table public.weekly_calls add column if not exists held int;
create unique index if not exists weekly_calls_pekjy on public.weekly_calls(project_id, employee_id, kw, year);
