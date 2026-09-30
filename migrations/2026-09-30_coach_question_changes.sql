-- Coach-Fragen: der Auftraggeber darf sie einsehen, bewerten, aendern, neue vorschlagen und
-- ablehnen. Nichts davon wird sofort scharf, ausser der Bewertung.
--
-- Unterschied zum Wissensregister: dort schlagen WIR vor und der Kunde bestaetigt
-- (kb_change_propose verlangt perm 'wissen' edit). Hier ist es umgekehrt, der Kunde schlaegt vor
-- und wir geben frei. Deshalb eine eigene Tabelle und eigene Funktionen statt einer Erweiterung.

-- ── 1 Bewertung des Auftraggebers, getrennt von der Note des KI-Pruefers ────────────────────
-- quality/judge_note bleiben unberuehrt: zwei verschiedene Urteile, die nie verschmelzen duerfen.
alter table public.coach_questions add column if not exists client_quality int;
alter table public.coach_questions add column if not exists client_quality_note text;
alter table public.coach_questions add column if not exists client_quality_at timestamptz;
alter table public.coach_questions add column if not exists client_quality_by uuid;
alter table public.coach_questions add column if not exists client_quality_by_name text;
comment on column public.coach_questions.client_quality is
  'Bewertung des Auftraggebers, 1 bis 5. Steht sofort, ohne Freigabe: eine Note aendert nicht, was ein Agent lernt.';

-- ── 2 Vorschlaege ──────────────────────────────────────────────────────────────────────────
create table if not exists public.coach_question_changes (
  id               uuid primary key default gen_random_uuid(),
  project_id       text not null,
  question_id      uuid references public.coach_questions(id) on delete set null,   -- null bei 'new'
  change_kind      text not null check (change_kind in ('edit','new','reject')),
  old_value        jsonb,                -- Stand der Frage zum Zeitpunkt des Vorschlags
  new_value        jsonb,                -- vorgeschlagener Stand ('edit'/'new')
  note             text,                 -- Begruendung; bei 'reject' Pflicht (in der Funktion geprueft)
  proposed_by      uuid,
  proposed_by_name text,
  proposed_at      timestamptz not null default now(),
  status           text not null default 'open' check (status in ('open','approved','rejected','withdrawn')),
  decided_by       uuid,
  decided_by_name  text,
  decided_at       timestamptz,
  decision_note    text,
  applied_question_id uuid,              -- bei 'new': die angelegte Frage
  reminded_at      timestamptz,          -- fuer die spaetere Erinnerung, heute noch ungenutzt
  reminder_count   int not null default 0,
  escalated_at     timestamptz
);
create index if not exists coach_qc_offen on public.coach_question_changes(project_id, status, proposed_at desc);
create index if not exists coach_qc_frage on public.coach_question_changes(question_id);
alter table public.coach_question_changes enable row level security;

-- Lesen: intern wie beim Wissen, und der Auftraggeber seine eigenen Projektvorschlaege.
drop policy if exists coach_qc_sel_internal on public.coach_question_changes;
create policy coach_qc_sel_internal on public.coach_question_changes for select using (
  coalesce((perm(auth.uid(),'wissen')->>'visible')::boolean,false) and perm_proj_ok(auth.uid(),'wissen',project_id));
drop policy if exists coach_qc_sel_client on public.coach_question_changes;
create policy coach_qc_sel_client on public.coach_question_changes for select using (
  get_my_client_project_id() is not null and project_id = get_my_client_project_id());
-- Schreiben ausschliesslich ueber die Funktionen unten. Keine INSERT/UPDATE-Policy, mit Absicht.

-- ── 3 Der Auftraggeber sieht auch blockierte Fragen ────────────────────────────────────────
-- Sonst verschwindet eine Frage nach der Ablehnung aus seiner Liste und er sieht nie, was daraus
-- wurde. In der Oberflaeche stehen die aktiven vorn, die blockierten hinter einem Filter.
drop policy if exists coach_q_client on public.coach_questions;
create policy coach_q_client on public.coach_questions for select using (
  status in ('active','blocked') and get_my_client_project_id() is not null
  and project_id = get_my_client_project_id());
