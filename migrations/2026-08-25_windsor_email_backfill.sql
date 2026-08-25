-- Bestands-Anreicherung: cvs.email aus windsor_leads.email nachziehen (Zuordnung ueber die Meta-Lead-ID:
-- cvs.extra.lead_id = windsor_leads.lead_id). ERST AUSFUEHREN, wenn windsor_leads.email fuer die Altrows
-- gefuellt ist (einmaliger Windsor-Voll-Sync mit weitem Fenster ODER geliefertes File in windsor_leads.email).
-- Setzt nur leere cvs.email (ueberschreibt nie eine bereits gepflegte Adresse). Idempotent.

-- Live-Spalte der windsor_leads-PK heisst id (text), NICHT lead_id (Connector-Schema weicht von der
-- 2026-08-17-Migration ab). cvs.extra.lead_id wird aus windsor_leads.id gefuellt -> Join ueber wl.id.
--
-- cvs.email hat einen UNIQUE-Index (idx_cvs_email_unique) und Windsor enthaelt doppelte Adressen
-- (dieselbe Person mehrfach beworben). Ein einzelnes UPDATE wuerde bei der ersten Kollision ALLES
-- abbrechen. Darum kollisionssicher: jede Adresse geht an GENAU EINEN Bewerber (den aeltesten per
-- created_at), bereits vergebene und weitere Dubletten bleiben leer (gehoeren in den Dubletten-Bereich).
with existing as (
  select lower(email) e from public.cvs where email is not null and email <> ''
),
cand as (
  select c.id as cv_id, wl.email,
         row_number() over (partition by lower(wl.email) order by c.created_at nulls last, c.id) as rn
  from public.cvs c
  join public.windsor_leads wl on c.extra->>'lead_id' = wl.id
  where (c.email is null or c.email = '')
    and wl.email is not null and wl.email like '%@%'
    and lower(wl.email) not in (select e from existing)
)
update public.cvs c
set    email = cand.email
from   cand
where  c.id = cand.cv_id and cand.rn = 1;

-- Kontrolle danach:
--   select count(*) from cvs where email is not null and email <> '';
--   select count(*) from cvs where source='meta' and (email is null or email='');
