-- =============================================================================
-- HR-Feedbackgespräche — Katalog, Gespräche, Antworten                 2026-07-27
-- =============================================================================
-- HR führt das Gespräch und trägt die Antworten ein (MA füllt nichts selbst aus).
-- MA sieht read-only: dass ein Gespräch ansteht, und die eigene Historie.
--
-- Katalog-Robustheit: Frage-IDENTITÄT ist stabil (feedback_questions.id wechselt
-- nie → Auswertung gruppiert darüber). Jede Antwort SNAPSHOTTET zusätzlich Wortlaut
-- und Typ zum Zeitpunkt des Gesprächs (prompt_snapshot/type_snapshot). Ändert HR
-- eine Frage, bleiben alte Antworten unverändert lesbar und eindeutig zugeordnet;
-- die Änderung wirkt nur auf künftige Gespräche. Fragen werden nie hart gelöscht
-- (active=false), damit question_id in alten Antworten referenzierbar bleibt.
--
-- Notenskala: Schulnote 1–5 (kosovarisch). 1 = sehr zufrieden (beste), 5 = sehr
-- unzufrieden (schlechteste). NIEDRIGER = BESSER. Folgefragen greifen bei
-- Unzufriedenheit, d.h. grade >= followup_show_if_grade_gte (z.B. >= 4).
--
-- Idempotent (if not exists / drop policy if exists / Seed nur wenn Katalog leer).
-- Anzuwenden im Supabase SQL-Editor. Voraussetzung: schema_auth.sql (is_admin()),
-- vacation_requests_schema.sql (get_my_employee_id()).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1  feedback_questions — konfigurierbarer Fragenkatalog (editierbar, reorderbar)
-- -----------------------------------------------------------------------------
create table if not exists public.feedback_questions (
  id                         uuid primary key default gen_random_uuid(),
  section                    text not null,                       -- Gruppierungslabel (Einstieg, …)
  order_index                int  not null default 0,             -- Reihenfolge (10,20,30… Platz zum Umsortieren)
  prompt                     text not null,
  type                       text not null check (type in ('text','grade')),
  active                     boolean not null default true,       -- Soft-Delete (nie hart löschen)
  followup_prompt            text,                                -- bedingte Folgefrage (nur bei grade)
  followup_show_if_grade_gte int check (followup_show_if_grade_gte between 1 and 5),  -- zeigt sich ab dieser Note
  followup_slots             int,                                 -- Anzahl Textfelder (z.B. 2 Gründe/Lösungen)
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now()
);
create index if not exists feedback_questions_order on public.feedback_questions (active, order_index);


-- -----------------------------------------------------------------------------
-- §2  feedback_sessions — ein Gespräch (gezogen oder manuell angelegt)
-- -----------------------------------------------------------------------------
create table if not exists public.feedback_sessions (
  id               uuid primary key default gen_random_uuid(),
  employee_id      uuid not null references public.employees(id) on delete cascade,
  status           text not null default 'scheduled' check (status in ('scheduled','done','skipped')),
  source           text not null default 'random'    check (source in ('random','manual')),
  scheduled_date   date not null default current_date,
  conducted_by     uuid references auth.users(id) on delete set null,
  conducted_by_name text,
  conducted_at     timestamptz,
  project_id       text,     -- Snapshot fürs Dashboard (Projekt-Vergleich)
  location         text,     -- Snapshot fürs Dashboard (Standort-Vergleich)
  created_at       timestamptz not null default now()
);
create index if not exists feedback_sessions_emp   on public.feedback_sessions (employee_id, scheduled_date);
create index if not exists feedback_sessions_sched on public.feedback_sessions (scheduled_date, status);


-- -----------------------------------------------------------------------------
-- §3  feedback_answers — eine Antwort je Frage je Gespräch (mit Snapshot)
-- -----------------------------------------------------------------------------
create table if not exists public.feedback_answers (
  id                        uuid primary key default gen_random_uuid(),
  session_id                uuid not null references public.feedback_sessions(id) on delete cascade,
  question_id               uuid references public.feedback_questions(id) on delete set null,  -- stabile Identität (Gruppierung)
  order_index               int  not null default 0,   -- Snapshot der Position (Rendering Historie)
  section                   text,                       -- Snapshot
  prompt_snapshot           text not null,              -- Snapshot des Wortlauts → immer lesbar
  type_snapshot             text not null check (type_snapshot in ('text','grade')),
  answer_text               text,                       -- bei type='text'
  grade                     int check (grade between 1 and 5),  -- bei type='grade' (1=beste, 5=schlechteste)
  followup_prompt_snapshot  text,
  followup_texts            jsonb,                      -- die 2 Gründe/Lösungsvorschläge
  created_at                timestamptz not null default now()
);
create index if not exists feedback_answers_session  on public.feedback_answers (session_id);
create index if not exists feedback_answers_question on public.feedback_answers (question_id);


-- -----------------------------------------------------------------------------
-- §4  RLS — HR/Management (is_admin) verwalten alles; Mitarbeiter sehen nur die
--     EIGENEN Gespräche/Antworten (read-only). Den Katalog braucht der MA nicht
--     (Wortlaut liegt als Snapshot in den Antworten) → Katalog nur is_admin.
-- -----------------------------------------------------------------------------
alter table public.feedback_questions enable row level security;
alter table public.feedback_sessions  enable row level security;
alter table public.feedback_answers   enable row level security;

-- Katalog: nur HR/Management
drop policy if exists feedback_questions_admin on public.feedback_questions;
create policy feedback_questions_admin on public.feedback_questions
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Gespräche: HR/Management alles …
drop policy if exists feedback_sessions_admin on public.feedback_sessions;
create policy feedback_sessions_admin on public.feedback_sessions
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
-- … Mitarbeiter nur eigene (nur lesen)
drop policy if exists feedback_sessions_own on public.feedback_sessions;
create policy feedback_sessions_own on public.feedback_sessions
  for select to authenticated using (employee_id = public.get_my_employee_id());

-- Antworten: HR/Management alles …
drop policy if exists feedback_answers_admin on public.feedback_answers;
create policy feedback_answers_admin on public.feedback_answers
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
-- … Mitarbeiter nur eigene (über die zugehörige Session, nur lesen)
drop policy if exists feedback_answers_own on public.feedback_answers;
create policy feedback_answers_own on public.feedback_answers
  for select to authenticated using (
    exists (select 1 from public.feedback_sessions s
             where s.id = feedback_answers.session_id
               and s.employee_id = public.get_my_employee_id()));

grant select, insert, update, delete on public.feedback_questions to authenticated;
grant select, insert, update, delete on public.feedback_sessions  to authenticated;
grant select, insert, update, delete on public.feedback_answers   to authenticated;


-- -----------------------------------------------------------------------------
-- §5  Realtime — damit Cockpit („erledigte verschwinden") und MA-Karte live
--     aktualisieren. Falls die Tabelle schon in der Publication liegt, wirft der
--     Befehl einen Fehler → dann einfach diese eine Zeile überspringen.
-- -----------------------------------------------------------------------------
alter publication supabase_realtime add table public.feedback_sessions;


-- -----------------------------------------------------------------------------
-- §6  Startkatalog-Seed (später im Editor änderbar) — nur wenn Katalog leer ist.
--     Sektionsnamen und Fragetexte exakt nach Vorgabe, inkl. der bedingten
--     Folgefragen (2 Gründe bei Unzufriedenheit; 2 Lösungsvorschläge bei den
--     Herausforderungen). Folgefragen greifen ab Note 4 (unzufrieden).
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from public.feedback_questions) then
    insert into public.feedback_questions
      (section, order_index, prompt, type, followup_prompt, followup_show_if_grade_gte, followup_slots)
    values
      ('Einstieg',          10, 'Wie war der letzte Monat - was lief gut, was nicht?', 'text',  null,                              null, null),
      ('Einstieg',          20, 'Bewertung',                                           'grade', 'Bitte 2 Gründe nennen',           4,    2),
      ('Aufgaben',          30, 'Woran arbeitest du, passt die Auslastung?',           'text',  null,                              null, null),
      ('Aufgaben',          40, 'Bewertung',                                           'grade', null,                              null, null),
      ('Herausforderungen', 50, 'Was bereitet täglich Probleme?',                      'text',  null,                              null, null),
      ('Herausforderungen', 60, 'Bewertung',                                           'grade', 'Bitte 2 Lösungsvorschläge nennen', 4,    2),
      ('Zusammenarbeit',    70, 'Spaß im Team',                                        'grade', null,                              null, null),
      ('Zusammenarbeit',    80, 'Support vom Vorgesetzten',                            'grade', null,                              null, null),
      ('Zusammenarbeit',    90, 'Längerfristig bleiben?',                              'text',  null,                              null, null),
      ('Abschluss',        100, 'Organisation im Büro',                                'grade', null,                              null, null),
      ('Abschluss',        110, 'Was ans Management weitergeben?',                     'text',  null,                              null, null);
  end if;
end $$;
