-- Windsor liefert ab 2026-08-26 zusaetzlich das Feld email bei Meta-Bewerbungen.
-- Spalte additiv anlegen, damit der naechtliche Windsor-Auftrag nicht scheitert. Der Import
-- (Edge Function applicant-import) nimmt sie danach nach cvs.email mit.
alter table public.windsor_leads add column if not exists email text;
