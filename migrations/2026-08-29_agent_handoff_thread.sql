-- Vorhaben 4, Umbau: die Übergabe als Gesprächsverlauf. thread = geordnete Beiträge [{agent,text,observation_id,at}];
-- die Kollegen nennen nacheinander ihren Befund, der letzte Beitrag ist die gemeinsame Schlussfolgerung.
alter table public.agent_handoffs add column if not exists thread jsonb;
