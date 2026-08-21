-- windsor_marketing: Bewerbungszeilen raus + Unique-Key fuer Windsor-Upsert.
-- Ohne Unique-Key kann Windsor nicht abgleichen (egal was in "Columns to Match" steht) -> Append -> Dubletten
-- (z.B. facebook_leads am 20.08. dreifach). facebook_leads sind BEWERBUNGEN, gehoeren in den Trichter, nicht
-- in die Marketing-Tabelle. Grain heute: 1 Zeile pro (datasource, date) fuer facebook/instagram (verifiziert).

-- 1) Bewerbungszeilen entfernen (gehoeren nicht in windsor_marketing)
delete from public.windsor_marketing where datasource = 'facebook_leads';

-- 2) Unique-Key = Windsors "Columns to Match" fuer echten Upsert statt Append
alter table public.windsor_marketing
  add constraint windsor_marketing_datasource_date_key unique (datasource, date);
