-- =============================================================================
-- Coach (Conny coacht) · Schnitt 1: Datenmodell                                 2026-09-18
-- Fragenbank je Partner aus dem Wissensspeicher (Register + Abschnitte), Einheiten je Mitarbeiter, Antworten.
-- Sichtbarkeit: Mitarbeiter nur eigene Einheiten/Antworten; Kunde nur Einheiten seines Projekts OHNE Antworten
-- (Trends und Themenlücken, keine Wörtlichkeit; User 2026-09-18); wir alles über Bereich 'wissen'.
-- Fragen tragen ihre Quelle (Fakt oder Abschnitt); ändert sich ein Fakt (Freigabe), werden die Fragen dazu 'stale'.
-- Schreiben in sessions/answers nur über die Edge Function coach-session (Service-Role), Flag über RPC.
-- =============================================================================
create table if not exists public.coach_questions (
  id            uuid primary key default gen_random_uuid(),
  project_id    text not null,
  kind          text not null check (kind in ('mc','gap','match','order','free')),
  difficulty    text not null check (difficulty in ('leicht','mittel','schwer')),
  topic         text not null,
  zielgebiet    text,
  prompt        text not null,
  options       jsonb,                 -- mc: [{key,text}] · match: {left:[..], right:[..]} · order: [schritte gemischt]
  answer        jsonb not null,        -- mc: {key} · gap: {accept:[..]} · match: {pairs:{left:right}} · order: {sequence:[..]} · free: {must:[..], nice:[..]}
  explanation   text,
  source_kind   text not null check (source_kind in ('fact','chunk')),
  source_id     uuid not null,
  source_label  text,
  source_stamp  timestamptz,
  status        text not null default 'active' check (status in ('active','blocked','stale')),
  gen_by        text not null default 'rule' check (gen_by in ('rule','ai')),
  fingerprint   text not null,          -- Dedupe je Partner: kind + source + prompt
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create unique index if not exists coach_questions_fp on public.coach_questions(project_id, fingerprint);
create index if not exists coach_questions_pick on public.coach_questions(project_id, status, topic, difficulty, kind);

create table if not exists public.coach_sessions (
  id            uuid primary key default gen_random_uuid(),
  employee_id   uuid not null references public.employees(id) on delete cascade,
  project_id    text not null,
  user_id       uuid,
  settings      jsonb not null default '{}'::jsonb,   -- {mode, topic, zielgebiet, minutes, difficulty, kinds}
  question_ids  uuid[] not null default '{}',
  status        text not null default 'open' check (status in ('open','done','abandoned')),
  points        numeric, max_points numeric, score numeric,          -- score 0..1
  topic_scores  jsonb,                                                -- {thema:{points,max}}
  started_at    timestamptz not null default now(),
  finished_at   timestamptz
);
create index if not exists coach_sessions_emp on public.coach_sessions(employee_id, started_at desc);
create index if not exists coach_sessions_proj on public.coach_sessions(project_id, started_at desc);

create table if not exists public.coach_answers (
  id            uuid primary key default gen_random_uuid(),
  session_id    uuid not null references public.coach_sessions(id) on delete cascade,
  question_id   uuid not null references public.coach_questions(id) on delete cascade,
  employee_id   uuid not null,
  project_id    text not null,
  kind          text not null,
  topic         text,
  answer        jsonb,
  points        numeric not null default 0,
  max_points    numeric not null default 1,
  feedback      text,
  rubric        jsonb,                  -- free: {hits:[..], missing:[..]}
  flagged       boolean not null default false,
  flag_note     text,
  seconds       int,
  answered_at   timestamptz not null default now()
);
create index if not exists coach_answers_emp on public.coach_answers(employee_id, answered_at desc);
create index if not exists coach_answers_q on public.coach_answers(question_id);

alter table public.coach_questions enable row level security;
alter table public.coach_sessions  enable row level security;
alter table public.coach_answers   enable row level security;

-- Fragen: intern (wissen sichtbar + Projekt), Mitarbeiter des Projekts (nur aktive), Kunde des Projekts (nur aktive; für Themen-Namen)
drop policy if exists coach_q_internal on public.coach_questions;
create policy coach_q_internal on public.coach_questions for select to authenticated
  using (coalesce((perm(auth.uid(),'wissen')->>'visible')::boolean,false) and perm_proj_ok(auth.uid(),'wissen',project_id));
drop policy if exists coach_q_employee on public.coach_questions;
create policy coach_q_employee on public.coach_questions for select to authenticated
  using (status = 'active' and project_id = public.get_my_employee_project_id());
drop policy if exists coach_q_client on public.coach_questions;
create policy coach_q_client on public.coach_questions for select to authenticated
  using (status = 'active' and public.get_my_client_project_id() is not null and project_id = public.get_my_client_project_id());
drop policy if exists coach_q_write on public.coach_questions;
create policy coach_q_write on public.coach_questions for all to authenticated
  using (perm_mode(auth.uid(),'wissen') = 'edit' and perm_proj_ok(auth.uid(),'wissen',project_id))
  with check (perm_mode(auth.uid(),'wissen') = 'edit' and perm_proj_ok(auth.uid(),'wissen',project_id));

-- Einheiten: eigener MA, Kunde (eigenes Projekt, Kopfdaten ohne Antworten), intern
drop policy if exists coach_s_own on public.coach_sessions;
create policy coach_s_own on public.coach_sessions for select to authenticated using (employee_id = public.get_my_employee_id());
drop policy if exists coach_s_client on public.coach_sessions;
create policy coach_s_client on public.coach_sessions for select to authenticated
  using (public.get_my_client_project_id() is not null and project_id = public.get_my_client_project_id());
drop policy if exists coach_s_internal on public.coach_sessions;
create policy coach_s_internal on public.coach_sessions for select to authenticated
  using (coalesce((perm(auth.uid(),'wissen')->>'visible')::boolean,false) and perm_proj_ok(auth.uid(),'wissen',project_id));

-- Antworten: eigener MA und intern. KEIN Kundenzugriff (Wörtlichkeit bleibt bei uns und dem Mitarbeiter).
drop policy if exists coach_a_own on public.coach_answers;
create policy coach_a_own on public.coach_answers for select to authenticated using (employee_id = public.get_my_employee_id());
drop policy if exists coach_a_internal on public.coach_answers;
create policy coach_a_internal on public.coach_answers for select to authenticated
  using (coalesce((perm(auth.uid(),'wissen')->>'visible')::boolean,false) and perm_proj_ok(auth.uid(),'wissen',project_id));

-- Frage melden („unklar“): nur eigene Antwort
create or replace function public.coach_flag(p_answer uuid, p_note text default null)
returns boolean language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update coach_answers set flagged = true, flag_note = nullif(btrim(coalesce(p_note,'')),'')
   where id = p_answer and employee_id = public.get_my_employee_id();
  get diagnostics n = row_count; return n > 0;
end $$;
revoke all on function public.coach_flag(uuid,text) from public;
grant execute on function public.coach_flag(uuid,text) to authenticated;

-- Wissen ändert sich → Fragen dazu veralten (werden vom Generator neu gebaut)
create or replace function public.coach_stale_on_fact() returns trigger language plpgsql as $$
begin
  if new.value is distinct from old.value or new.label is distinct from old.label or new.zielgebiet is distinct from old.zielgebiet
     or (old.status = 'active' and new.status is distinct from 'active') then
    update public.coach_questions set status = 'stale', updated_at = now() where source_kind = 'fact' and source_id = new.id and status = 'active';
  end if;
  return new;
end $$;
drop trigger if exists coach_stale_on_fact_trg on public.kb_facts;
create trigger coach_stale_on_fact_trg after update on public.kb_facts for each row execute function public.coach_stale_on_fact();

-- Gibt es für mein Projekt einen Coach? (Mitarbeiter-Portal blendet den Punkt sonst aus)
create or replace function public.coach_available()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('project_id', public.get_my_employee_project_id(),
    'questions', (select count(*) from coach_questions q where q.project_id = public.get_my_employee_project_id() and q.status = 'active'),
    'topics', (select coalesce(jsonb_agg(t order by t), '[]'::jsonb) from (select distinct topic as t from coach_questions q where q.project_id = public.get_my_employee_project_id() and q.status = 'active') x),
    'zielgebiete', (select coalesce(jsonb_agg(z order by z), '[]'::jsonb) from (select distinct zielgebiet as z from coach_questions q where q.project_id = public.get_my_employee_project_id() and q.status = 'active' and zielgebiet is not null) y),
    'today', (select count(*) from coach_sessions s where s.employee_id = public.get_my_employee_id() and s.status = 'done' and s.finished_at::date = current_date));
$$;
revoke all on function public.coach_available() from public;
grant execute on function public.coach_available() to authenticated;
