-- CV-Felder aus extra in echte Spalten — TEIL 2 (NACH dem Code-Deploy).
-- Entfernt die jetzt in echte Spalten übernommenen Keys aus extra. Erst ausführen,
-- wenn der neue Code (Felder in CV_COLS) live ist — sonst schreibt der Altcode sie
-- wieder in extra. Kein Datenverlust: die Werte stehen bereits in den Spalten (Teil 1).
-- id_card = Legacy-Alias, in Teil 1 nach id_number kopiert → hier mit aufräumen.

update public.cvs set
  extra = extra - 'primary_skill' - 'id_number' - 'id_card'
                - 'bank_name' - 'bank_account' - 'assessed_level' - 'hr_rating'
where extra ?| array['primary_skill','id_number','id_card','bank_name','bank_account','assessed_level','hr_rating'];
