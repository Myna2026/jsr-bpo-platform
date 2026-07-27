-- 2026-07-27  employees: tax_id + social_security aus extra entfernen
-- Kontext: Steuer-ID (tax_id) und Sozialversicherungs-Nr. (social_security) gibt es
-- beim Mitarbeiter fachlich nicht mehr. Sie waren nie echte Spalten, sondern lagen
-- im extra-JSONB-Sink. UI + Feld-Ampel wurden entfernt; hier der Daten-Cleanup.
-- Idempotent, reversibel nur über Backup (Werte werden gelöscht).

update public.employees
set extra = extra - 'tax_id' - 'social_security'
where extra ?| array['tax_id','social_security'];

-- Kontrolle: sollte 0 Zeilen liefern
-- select id, extra->'tax_id', extra->'social_security'
-- from public.employees
-- where extra ?| array['tax_id','social_security'];
