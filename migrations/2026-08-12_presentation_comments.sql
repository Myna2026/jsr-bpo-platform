-- =============================================================================
-- Kunden-Kommentare zu Berichten (Einweg + Gelesen-Status)                 2026-08-12
-- =============================================================================
-- Der Kunde markiert Stellen im veröffentlichten Bericht und kommentiert sie mit
-- vier Stufen (rot kritisch / grün lobend / amber neutral / schwarz Hinweis).
-- Anker: Folie (slide) + optionaler Element-Anker (anchor). Einweg (Kunde → Management);
-- „Gelesen/erledigt" setzt das Management (read_at). Cockpit zeigt nur den aktuellsten
-- Bericht — das ist Anzeige-Logik (Frontend), die Kommentare bleiben am jeweiligen Bericht.
--
-- Zuordnung Kunde↔Projekt AUSSCHLIESSLICH über get_my_client_project_id() (wie alle Kunden-
-- Views, keine zweite Logik). Kommentieren nur auf EIGENE, VERÖFFENTLICHTE Berichte.
-- Idempotent. Im Supabase SQL-Editor ausführen.
-- =============================================================================

create table if not exists public.presentation_comments (
  id              uuid primary key default gen_random_uuid(),
  presentation_id uuid not null references public.presentations(id) on delete cascade,
  project_id      text not null,                    -- = presentations.project_id (für RLS/Cockpit-Filter)
  slide           text,                             -- Folien-Key (title | <skill>:stunden | <skill>:calls | …)
  anchor          text,                             -- optionaler Anker (Freitext-Label auf der Folie)
  severity        text not null default 'black' check (severity in ('red','green','amber','black')),
  body            text not null,
  author_name     text,
  created_by      uuid references auth.users(id) on delete set null,
  read_at         timestamptz,                      -- Management „gelesen/erledigt"
  read_by         text,
  created_at      timestamptz not null default now()
);
create index if not exists idx_pres_comments_pres on public.presentation_comments(presentation_id);
create index if not exists idx_pres_comments_proj on public.presentation_comments(project_id, created_at desc);
grant select, insert, update, delete on public.presentation_comments to authenticated;

alter table public.presentation_comments enable row level security;

-- Kunde: eigenes Projekt LESEN.
drop policy if exists pres_comments_client_read on public.presentation_comments;
create policy pres_comments_client_read on public.presentation_comments
  for select to authenticated
  using ( project_id = public.get_my_client_project_id() );

-- Kunde: KOMMENTIEREN nur auf eigene, VERÖFFENTLICHTE Berichte (Einweg). Kein Update/Delete.
drop policy if exists pres_comments_client_insert on public.presentation_comments;
create policy pres_comments_client_insert on public.presentation_comments
  for insert to authenticated
  with check (
    project_id = public.get_my_client_project_id()
    and created_by = auth.uid()
    and exists (select 1 from public.presentations p
                where p.id = presentation_id and p.published = true and p.project_id = project_id)
  );

-- Management: alles lesen + Gelesen-Status setzen (Update) + löschen.
drop policy if exists pres_comments_mgmt_all on public.presentation_comments;
create policy pres_comments_mgmt_all on public.presentation_comments
  for all to authenticated
  using      ( public.is_management() )
  with check ( public.is_management() );

-- ── Nachweis (optional) ──────────────────────────────────────────────────────
-- Als Kunde: insert nur auf eigenen published Bericht möglich; select nur eigenes Projekt.
-- Als Management: select alle; update read_at möglich.
