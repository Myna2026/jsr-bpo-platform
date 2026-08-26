-- Lena, die sechste Assistentin: alles rund um Mitarbeiter (Urlaubsanträge, Abwesenheiten, Mitarbeiterpflege,
-- Portalzugänge) und der Mitarbeiter-Chat. Sie MELDET Auffälligkeiten/Verstöße, sie sanktioniert nicht.
-- Neue Sichtbarkeit 'admin' = Management UND HR (is_admin()). Findings gehen an Management+HR, nicht öffentlich.

begin;

-- Sichtbarkeit um 'admin' (Management+HR) erweitern.
alter table public.ai_agents drop constraint if exists ai_agents_visibility_check;
alter table public.ai_agents add constraint ai_agents_visibility_check check (visibility in ('all','management','admin'));

-- RLS: 'all' für jeden, 'management' fürs Management, 'admin' für Management+HR.
drop policy if exists ai_agents_sel on public.ai_agents;
create policy ai_agents_sel on public.ai_agents for select to authenticated
  using ( visibility = 'all'
       or (visibility = 'management' and public.is_management())
       or (visibility = 'admin' and public.is_admin()) );

insert into public.ai_agents(key,name,tagline,domain,accent,capabilities,where_keys,outward_facing,disclosure,decision_authority,visibility,seq) values
 ('lena','Lena','Kümmert sich um alles rund um Mitarbeiter.','Mitarbeiter','#db2777',
   array[
     'Datenpflege prüfen: fehlende Angaben, unplausible Einträge, Verträge ohne Daten',
     'Liegengebliebene Urlaubsanträge und offene Vorgänge melden',
     'Portalzugänge der Mitarbeiter im Blick behalten',
     'Im Mitarbeiter-Chat bei Verstößen anschlagen: Beleidigungen, Beschimpfungen, Mobbing, Betrugsversuche',
     'Beim Chat gilt: sie schlägt an, wenn etwas passiert. Sie liest nicht mit, um zu berichten.'
   ],
   array['urlaubantraege','absences','employees','appusers'], false, null,
   '{"darf":["Auffälligkeiten und Verstöße an Management und HR melden"],"darf_nicht":["sanktionieren oder verwarnen — wer verwarnt oder handelt, ist HR"]}'::jsonb,
   'admin', 6)
on conflict (key) do nothing;

commit;
