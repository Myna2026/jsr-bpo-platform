-- =============================================================================
-- Besprechungsnotizen je Projekt (Overhead-Meetings)  Schnitt 1: Datenmodell + RLS  2026-08-25
-- =============================================================================
-- Interne Steuerung: mehrmals/Woche Overhead-Runde je Projekt. Loest das Word-Dokument ab.
-- Drei Tabellen, angelehnt an bewaehrte Muster im Haus:
--   meeting_notes         = eine Besprechung (Projekt, optional Skill, Datum, Titel, laufender Body)
--   meeting_note_items    = strukturierte Punkte, WICHTIGKEITS-Ampel (gruen/gelb/rot) UND getrennter
--                           Erledigt-Haken (bewusst zwei Felder -> filterbar). Carry-over wie report_measures.
--   meeting_note_comments = Overhead-Kommentare (Einweg-INSERT wie presentation_comments), kein Notiz-Edit.
--
-- Rechte (RLS ueber SECURITY-DEFINER-Helfer):
--   Schreiben  = Management (Shkurte) ODER Projektleiter GENAU seines Projekts (Ylli/Giganetz, Edi/HolidayCheck)
--   Kommentieren = zugeordnetes OVERHEAD des Projekts (offene project_assignments-Zuweisung), NUR insert
--   Lesen      = Schreiber + zugeordnetes Overhead
-- Zuordnung strikt aus employees.project_assignments (jsonb, end_date null = offen) bzw. flach project_id.
-- Additiv/idempotent. Kein UI in diesem Schnitt.
-- =============================================================================

begin;

-- ── Helfer ────────────────────────────────────────────────────────────────────
-- Ist der aufrufende User (sein Mitarbeiter) dem Projekt zugeordnet? Flach (project_id) ODER
-- offene jsonb-Zuweisung (end_date null). project_id ist Text ('proj_hc_...').
create or replace function public.mn_employee_on_project(p_project_id text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.employees e
    where e.id = public.get_my_employee_id()
      and ( e.project_id::text = p_project_id
         or exists (select 1 from jsonb_array_elements(coalesce(e.project_assignments,'[]'::jsonb)) a
                    where a->>'project_id' = p_project_id and (a->>'end_date') is null) )
  );
$$;

-- Zugeordnetes OVERHEAD (Teamleiter/Trainer/QM/Projektleiter) auf dem Projekt -> darf kommentieren.
create or replace function public.mn_is_overhead_on_project(p_project_id text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.employees e
    where e.id = public.get_my_employee_id()
      and e.position in ('Teamleiter','Trainer','QM','Projektleiter')
      and ( e.project_id::text = p_project_id
         or exists (select 1 from jsonb_array_elements(coalesce(e.project_assignments,'[]'::jsonb)) a
                    where a->>'project_id' = p_project_id and (a->>'end_date') is null) )
  );
$$;

-- Schreiben: Management global ODER Projektleiter(-Rolle) auf genau diesem Projekt.
create or replace function public.mn_can_write(p_project_id text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_management()
     or ( exists (select 1 from public.app_users au
                  where au.user_id = auth.uid() and au.active and 'projektleiter' = any(au.role_keys))
          and public.mn_employee_on_project(p_project_id) );
$$;

-- Lesen: Schreiber ODER zugeordnetes Overhead.
create or replace function public.mn_can_read(p_project_id text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.mn_can_write(p_project_id) or public.mn_is_overhead_on_project(p_project_id);
$$;

revoke all on function public.mn_employee_on_project(text)   from public;
revoke all on function public.mn_is_overhead_on_project(text) from public;
revoke all on function public.mn_can_write(text)             from public;
revoke all on function public.mn_can_read(text)              from public;
grant execute on function public.mn_employee_on_project(text)   to authenticated;
grant execute on function public.mn_is_overhead_on_project(text) to authenticated;
grant execute on function public.mn_can_write(text)             to authenticated;
grant execute on function public.mn_can_read(text)              to authenticated;

-- ── Besprechung ───────────────────────────────────────────────────────────────
create table if not exists public.meeting_notes (
  id              uuid primary key default gen_random_uuid(),
  project_id      text not null,
  skill           text,                          -- null = ganzes Projekt (HC: Sales+Support zusammen)
  meeting_date    date not null default (now() at time zone 'Europe/Berlin')::date,
  title           text,
  body            text not null default '',       -- laufende Notizen (Freitext, KI-saeuberbar)
  created_by      uuid references auth.users(id) on delete set null,
  created_by_name text,
  updated_by_name text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists idx_meeting_notes_scope on public.meeting_notes(project_id, meeting_date desc);
alter table public.meeting_notes enable row level security;
drop policy if exists meeting_notes_read  on public.meeting_notes;
drop policy if exists meeting_notes_write on public.meeting_notes;
create policy meeting_notes_read  on public.meeting_notes for select to authenticated using (public.mn_can_read(project_id));
create policy meeting_notes_write on public.meeting_notes for all    to authenticated using (public.mn_can_write(project_id)) with check (public.mn_can_write(project_id));
grant select, insert, update, delete on public.meeting_notes to authenticated;

-- ── Punkte (Wichtigkeits-Ampel + getrennter Erledigt-Haken, Carry-over) ───────
create table if not exists public.meeting_note_items (
  id              uuid primary key default gen_random_uuid(),
  note_id         uuid references public.meeting_notes(id) on delete set null,  -- Herkunfts-Besprechung (Punkt ueberlebt Loeschen)
  project_id      text not null,                 -- denormalisiert: Carry-over/Filter unabhaengig von der Besprechung
  skill           text,                          -- optional: Punkt betrifft nur einen Skill (sonst null = ganzes Projekt)
  text            text not null,
  importance      text not null default 'green' check (importance in ('green','amber','red')),  -- WICHTIGKEIT
  done            boolean not null default false,  -- ERLEDIGT (getrennt von Wichtigkeit)
  done_at         timestamptz,
  created_year    int, created_kw int,           -- Woche der Erfassung (Carry-over/Zusammenfassung)
  done_year       int, done_kw int,
  seq             int not null default 0,
  created_by      uuid references auth.users(id) on delete set null,
  created_by_name text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists idx_meeting_note_items_scope on public.meeting_note_items(project_id, done, created_year, created_kw);
create index if not exists idx_meeting_note_items_note  on public.meeting_note_items(note_id);
alter table public.meeting_note_items enable row level security;
drop policy if exists meeting_note_items_read  on public.meeting_note_items;
drop policy if exists meeting_note_items_write on public.meeting_note_items;
create policy meeting_note_items_read  on public.meeting_note_items for select to authenticated using (public.mn_can_read(project_id));
create policy meeting_note_items_write on public.meeting_note_items for all    to authenticated using (public.mn_can_write(project_id)) with check (public.mn_can_write(project_id));
grant select, insert, update, delete on public.meeting_note_items to authenticated;

-- ── Overhead-Kommentare (Einweg-INSERT, kein Notiz-Edit) ──────────────────────
create table if not exists public.meeting_note_comments (
  id           uuid primary key default gen_random_uuid(),
  note_id      uuid not null references public.meeting_notes(id) on delete cascade,
  item_id      uuid references public.meeting_note_items(id) on delete cascade,  -- optional: Kommentar am Einzelpunkt
  project_id   text not null,                    -- = meeting_notes.project_id (RLS/Filter)
  body         text not null,
  author_name  text,
  created_by   uuid references auth.users(id) on delete set null,
  read_at      timestamptz,                      -- Schreiber „gelesen/erledigt"
  read_by      text,
  created_at   timestamptz not null default now()
);
create index if not exists idx_meeting_note_comments_note on public.meeting_note_comments(note_id, created_at desc);
alter table public.meeting_note_comments enable row level security;
drop policy if exists meeting_note_comments_read   on public.meeting_note_comments;
drop policy if exists meeting_note_comments_insert on public.meeting_note_comments;
drop policy if exists meeting_note_comments_manage on public.meeting_note_comments;
-- Lesen: alle Beteiligten (Schreiber + Overhead).
create policy meeting_note_comments_read on public.meeting_note_comments for select to authenticated
  using (public.mn_can_read(project_id));
-- Kommentieren: jeder Beteiligte (Overhead darf so kommentieren, ohne Notiz-Schreibrecht). Nur eigene Zeile.
create policy meeting_note_comments_insert on public.meeting_note_comments for insert to authenticated
  with check (public.mn_can_read(project_id) and created_by = auth.uid());
-- Gelesen-Status setzen: nur Schreiber.
create policy meeting_note_comments_manage on public.meeting_note_comments for update to authenticated
  using (public.mn_can_write(project_id)) with check (public.mn_can_write(project_id));
-- Loeschen (Moderation): nur Schreiber.
drop policy if exists meeting_note_comments_delete on public.meeting_note_comments;
create policy meeting_note_comments_delete on public.meeting_note_comments for delete to authenticated
  using (public.mn_can_write(project_id));
grant select, insert, update, delete on public.meeting_note_comments to authenticated;

commit;
