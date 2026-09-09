-- Gemeinsamer Verbesserungs-/Arbeitsplan (Kunde ↔ TIVE), je Projekt. Lebendes Dokument: Kunde nennt Punkte,
-- wir hinterlegen Maßnahmen. Baumstruktur (parent_id), Priorität als Ampel (4 Stufen), Fortschritt je Unterpunkt
-- (Hauptpunkt rollt im Frontend hoch), Fristen, Herkunft (client|intern), Kommentare beidseitig.
-- Zugriff: Kunde (eigenes Projekt) · Teamleitung des Projekts · Management/HR. Agenten NICHT.

create table if not exists public.improvement_items (
  id             uuid primary key default gen_random_uuid(),
  project_id     text not null references public.projects(id) on delete cascade,
  parent_id      uuid references public.improvement_items(id) on delete cascade,
  title          text not null,
  measures       text,                                   -- unser Freitext: was wir tun
  priority       text not null default 'wichtig' check (priority in ('sehr_wichtig','wichtig','notwendig','schoen')),
  status         text not null default 'offen'   check (status in ('offen','laeuft','erledigt','zurueckgestellt')),
  progress       int  not null default 0 check (progress between 0 and 100),  -- bei Unterpunkten gesetzt; Hauptpunkt = Mittel der Kinder (Frontend)
  due_date       date,
  origin         text not null default 'intern' check (origin in ('client','intern')),
  sort_order     int  not null default 0,
  created_by     uuid,
  created_by_name text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists improvement_items_proj_idx on public.improvement_items(project_id, parent_id, sort_order);

create table if not exists public.improvement_comments (
  id          uuid primary key default gen_random_uuid(),
  item_id     uuid not null references public.improvement_items(id) on delete cascade,
  project_id  text not null references public.projects(id) on delete cascade,   -- denormalisiert für RLS
  side        text not null check (side in ('client','team')),
  author_uid  uuid,
  author_name text,
  body        text not null,
  created_at  timestamptz not null default now()
);
create index if not exists improvement_comments_item_idx on public.improvement_comments(item_id, created_at);

alter table public.improvement_items    enable row level security;
alter table public.improvement_comments enable row level security;
grant select, insert, update, delete on public.improvement_items to authenticated;
grant select, insert, delete on public.improvement_comments to authenticated;

-- ── Prädikate (inline): Sichtbarkeit / interne Seite / Kunden-Seite je Projekt ──
-- Sichtbar = Kunde(eigenes) ODER mgmt/hr ODER Teamleitung des Projekts.
-- items
drop policy if exists imp_items_select on public.improvement_items;
create policy imp_items_select on public.improvement_items for select to authenticated using (
  (public.get_my_client_project_id() is not null and project_id = public.get_my_client_project_id())
  or public.is_management() or public.is_hr()
  or (public.is_planner() and public.get_my_employee_project_id() = project_id));
-- Kunde legt Punkte an (origin='client'); Team legt an (origin='intern').
drop policy if exists imp_items_insert_client on public.improvement_items;
create policy imp_items_insert_client on public.improvement_items for insert to authenticated with check (
  origin='client' and public.get_my_client_project_id() is not null and project_id = public.get_my_client_project_id());
drop policy if exists imp_items_insert_team on public.improvement_items;
create policy imp_items_insert_team on public.improvement_items for insert to authenticated with check (
  origin='intern' and (public.is_management() or public.is_hr() or (public.is_planner() and public.get_my_employee_project_id() = project_id)));
-- Ändern/Löschen: das Team führt den Plan (Maßnahmen/Fortschritt/Status/Frist/Priorität).
drop policy if exists imp_items_update_team on public.improvement_items;
create policy imp_items_update_team on public.improvement_items for update to authenticated using (
  public.is_management() or public.is_hr() or (public.is_planner() and public.get_my_employee_project_id() = project_id))
  with check (public.is_management() or public.is_hr() or (public.is_planner() and public.get_my_employee_project_id() = project_id));
drop policy if exists imp_items_delete_team on public.improvement_items;
create policy imp_items_delete_team on public.improvement_items for delete to authenticated using (
  public.is_management() or public.is_hr() or (public.is_planner() and public.get_my_employee_project_id() = project_id));

-- comments: beide Seiten lesen + schreiben (Seite passend), löschen eigene.
drop policy if exists imp_comments_select on public.improvement_comments;
create policy imp_comments_select on public.improvement_comments for select to authenticated using (
  (public.get_my_client_project_id() is not null and project_id = public.get_my_client_project_id())
  or public.is_management() or public.is_hr()
  or (public.is_planner() and public.get_my_employee_project_id() = project_id));
drop policy if exists imp_comments_insert_client on public.improvement_comments;
create policy imp_comments_insert_client on public.improvement_comments for insert to authenticated with check (
  side='client' and public.get_my_client_project_id() is not null and project_id = public.get_my_client_project_id());
drop policy if exists imp_comments_insert_team on public.improvement_comments;
create policy imp_comments_insert_team on public.improvement_comments for insert to authenticated with check (
  side='team' and (public.is_management() or public.is_hr() or (public.is_planner() and public.get_my_employee_project_id() = project_id)));
