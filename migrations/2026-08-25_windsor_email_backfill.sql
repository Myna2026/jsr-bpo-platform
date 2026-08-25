-- Bestands-Anreicherung: cvs.email aus windsor_leads.email nachziehen (Zuordnung ueber die Meta-Lead-ID:
-- cvs.extra.lead_id = windsor_leads.lead_id). ERST AUSFUEHREN, wenn windsor_leads.email fuer die Altrows
-- gefuellt ist (einmaliger Windsor-Voll-Sync mit weitem Fenster ODER geliefertes File in windsor_leads.email).
-- Setzt nur leere cvs.email (ueberschreibt nie eine bereits gepflegte Adresse). Idempotent.

update public.cvs c
set    email = wl.email
from   public.windsor_leads wl
where  c.extra->>'lead_id' = wl.lead_id
  and  wl.email is not null and wl.email like '%@%'
  and  (c.email is null or c.email = '');

-- Kontrolle danach:
--   select count(*) from cvs where email is not null and email <> '';
--   select count(*) from cvs where source='meta' and (email is null or email='');
