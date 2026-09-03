-- Postfach: Tags (Zustand, frei anlegbar) + Ordner (Ablage) + Sortier-/Filter-Grundlage.
-- Tags und Ordner liegen auf der KONVERSATION (conv_key = 'cv:'+cv_id bzw. 'addr:'+Adresse), nicht auf der
-- einzelnen Mail, damit ein spaeter eingehender Reply die Markierung/Ablage nicht verliert.
create table if not exists public.mail_tags (
  id uuid primary key default gen_random_uuid(), name text unique not null, color text default '#0F5661', created_at timestamptz default now());
create table if not exists public.mail_folders (
  id uuid primary key default gen_random_uuid(), name text unique not null, created_at timestamptz default now());
create table if not exists public.mail_conversation_meta (
  conv_key text primary key, tags text[] not null default '{}', folder text, updated_at timestamptz default now());

alter table public.mail_tags enable row level security;
alter table public.mail_folders enable row level security;
alter table public.mail_conversation_meta enable row level security;

drop policy if exists mtags_all on public.mail_tags;
create policy mtags_all on public.mail_tags for all to authenticated using (public.is_management() or public.is_hr()) with check (public.is_management() or public.is_hr());
drop policy if exists mfolders_all on public.mail_folders;
create policy mfolders_all on public.mail_folders for all to authenticated using (public.is_management() or public.is_hr()) with check (public.is_management() or public.is_hr());
drop policy if exists mconvmeta_all on public.mail_conversation_meta;
create policy mconvmeta_all on public.mail_conversation_meta for all to authenticated using (public.is_management() or public.is_hr()) with check (public.is_management() or public.is_hr());

-- Startsatz Tags (die vom User genannten Beispiele; frei aenderbar/loeschbar). Keine Start-Ordner.
insert into public.mail_tags(name,color) values
  ('erledigt','#16a34a'),('wartet auf Antwort','#d97706'),('Termin vereinbart','#0891b2'),('Rückfrage','#7c3aed')
  on conflict (name) do nothing;
