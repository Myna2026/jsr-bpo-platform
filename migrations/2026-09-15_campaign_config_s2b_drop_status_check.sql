-- Schnitt 2b: call_leads.status ist jetzt config-getrieben (= Knopf-key), daher die feste CHECK-Liste entfernen.
-- Broadening only; laufende Aktion (open/no_answer/rejected/appointment) bleibt gueltig.
alter table public.call_leads drop constraint if exists call_leads_status_check;
