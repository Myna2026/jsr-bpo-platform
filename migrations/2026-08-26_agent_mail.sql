-- Absender-Postfach je Agent im Register. Adresse + Anzeigename kommen aus ai_agents, das Passwort je Agent
-- als eigenes Supabase-Secret ZOHO_SMTP_PASS_<KEY> (nie in die DB). So schreibt jeder Agent aus seinem
-- eigenen Zoho-Postfach (Clara Bewerber, Max Erinnerungen, …).
alter table public.ai_agents add column if not exists email text;          -- Postfach-Adresse (SMTP-User = From)
alter table public.ai_agents add column if not exists mail_from_name text;  -- Anzeigename der Absenderadresse

update public.ai_agents set email='clara@25hrs.net', mail_from_name='25HRS Recruiting' where key='clara';
update public.ai_agents set email='max@25hrs.net',   mail_from_name='25HRS'           where key='max';
