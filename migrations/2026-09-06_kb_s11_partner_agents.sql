-- Wissensspeicher Schnitt 11: Partner-Agenten als Datenmodell (Name/Farbe/Avatar/Charakter/Begrüßung je Partner),
-- damit sie sich wie Kollegen anfühlen (Carlos != Holger) und ohne Code verwaltet werden können. Name+Farbe
-- wandern aus dem hartcodierten Frontend in die DB. Foto optional (Upload in der Partner-Verwaltung); ohne Foto
-- greift das gezeichnete Gesicht (face_key, Entwurf B). Avatare liegen im öffentlichen Bucket agent-avatars.

create table if not exists public.partner_agents (
  project_id  text primary key references public.projects(id) on delete cascade,
  name        text not null,
  color       text not null default '#0F5661',
  avatar_url  text,                         -- hochgeladenes Foto; null -> gezeichnetes Gesicht
  face_key    text,                         -- gezeichnetes Fallback-Gesicht (carlos/holger/georg/fabian/default)
  greeting    text,                         -- Begrüßung im Konsolen-Kopf
  character   text,                         -- Charakter/Ton für den Antwort-Motor
  updated_at  timestamptz not null default now(),
  updated_by  uuid
);

alter table public.partner_agents enable row level security;
-- Lesen: jeder eingeloggte Nutzer (Name/Farbe/Avatar/Begrüßung sind nicht sensibel; beide Portale brauchen sie).
drop policy if exists partner_agents_sel on public.partner_agents;
create policy partner_agents_sel on public.partner_agents for select using (auth.role() = 'authenticated');
-- Ändern: nur Management (Partner-Verwaltung).
drop policy if exists partner_agents_write on public.partner_agents;
create policy partner_agents_write on public.partner_agents for all using (public.is_management()) with check (public.is_management());
grant select, insert, update, delete on public.partner_agents to authenticated;

-- Startwerte: die vier Partner mit Farbe, Charakter und einer Begrüßung, die zur Person passt. Editierbar in S12.
insert into public.partner_agents (project_id, name, color, face_key, greeting, character) values
 ('proj_cd_c9d0e1f2','Carlos','#F5B301','carlos',
   'Servus, ich bin Carlos. Egal ob Abflug, Transfer oder Zielgebiet, ich schau in den Condor-Unterlagen für dich nach.',
   'Du bist Carlos, der Kollege fürs Condor-Reisegeschäft. Dein Zuhause sind Flüge, Transfers und Zielgebiete. Locker, zupackend, freundlich (ein „Servus" darf sein). Kurz und konkret.'),
 ('proj_hc_a1b2c3d4','Holger','#3B82F6','holger',
   'Hallo, Holger hier. Bei Hotels und Bewertungen bin ich zu Hause, sag mir einfach, worum es geht.',
   'Du bist Holger, der Kollege für HolidayCheck. Dein Zuhause sind Hotels, Bewertungen und Abläufe. Ruhig, sachlich, zuverlässig, ohne Schnörkel.'),
 ('proj_gn_e5f6a7b8','Georg','#EC4899','georg',
   'Moin, Georg am Apparat. Fragen zu Anschluss, Technik oder Ablauf? Leg einfach los.',
   'Du bist Georg, der Kollege für Giganetz. Du kennst Glasfaser, Anschlüsse, Technik und Abläufe. Direkt, technisch versiert, hilfsbereit.'),
 ('proj_fb_a3b4c5d6','Fabian','#8B5CF6','fabian',
   'Hey, ich bin Fabian. Ob Produkt, Bestellung oder Mitgliedschaft, frag mich einfach.',
   'Du bist Fabian, der Kollege für Fabletics. Du kennst Produkte, Bestellungen, Mitgliedschaft und Retouren. Frisch, motiviert, freundlich.')
on conflict (project_id) do nothing;

-- Öffentlicher Bucket für die Avatare (Fotos sind nicht sensibel; öffentliche URL wie presentation-assets). 3 MB.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('agent-avatars','agent-avatars', true, 3145728, array['image/png','image/jpeg','image/webp'])
on conflict (id) do update set public=true, file_size_limit=3145728, allowed_mime_types=array['image/png','image/jpeg','image/webp'];

drop policy if exists "agent_avatars write" on storage.objects;
create policy "agent_avatars write" on storage.objects for all
  using (bucket_id='agent-avatars' and public.is_management())
  with check (bucket_id='agent-avatars' and public.is_management());
