-- Beobachtungen tragen Projekt und Skill als FELD (nicht nur im Text), damit der Gefragte im Dialog
-- gezielt suchen kann statt zu raten. Wo eine Beobachtung global ist (Posteingang, Bank/Ausweis über
-- alle MA), bleiben die Felder null.
alter table public.agent_observations add column if not exists project_id text;
alter table public.agent_observations add column if not exists skill text;
