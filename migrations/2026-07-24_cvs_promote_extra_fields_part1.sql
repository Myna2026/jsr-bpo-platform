-- CV-Felder aus extra in echte Spalten — TEIL 1 (vor dem Code-Deploy).
-- Legt 6 Spalten an und kopiert die Werte aus extra. Die extra-Keys BLEIBEN vorerst
-- (Zero-Gap: solange der alte Code noch live ist, schreibt er weiter nach extra).
-- Teil 2 (extra-Cleanup) erst NACH dem Deploy einspielen.
-- Kein Datenverlust: coalesce lässt einen evtl. schon vorhandenen Spaltenwert gewinnen.

alter table public.cvs
  add column if not exists primary_skill  text,
  add column if not exists id_number      text,
  add column if not exists bank_name      text,
  add column if not exists bank_account   text,
  add column if not exists assessed_level text,
  add column if not exists hr_rating      text;

update public.cvs set
  primary_skill  = coalesce(primary_skill,  extra->>'primary_skill'),
  id_number      = coalesce(id_number,      extra->>'id_number', extra->>'id_card'),  -- Legacy-Alias id_card mitnehmen
  bank_name      = coalesce(bank_name,      extra->>'bank_name'),
  bank_account   = coalesce(bank_account,   extra->>'bank_account'),
  assessed_level = coalesce(assessed_level, extra->>'assessed_level'),
  hr_rating      = coalesce(hr_rating,      extra->>'hr_rating')
where extra ?| array['primary_skill','id_number','id_card','bank_name','bank_account','assessed_level','hr_rating'];
