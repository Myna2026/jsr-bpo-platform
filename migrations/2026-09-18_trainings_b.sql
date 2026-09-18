-- Schulungen: Link dauerhaft nutzbar. Nach der PIN wählt die Person: zugewiesene Schulung, „Überrasch mich“ oder ein Thema.
-- Dafür trägt jede geprüfte Frage Miriams drei Ebenen (Warum, Einwand, Anwendung) direkt in der Fragenbank (nachts befüllt),
-- und ein Durchlauf kann eine eigene Fragenkopie haben (run_questions), wenn er nicht die Schulung des Links ist.
alter table public.coach_questions add column if not exists layers jsonb, add column if not exists layers_at timestamptz;
alter table public.training_runs add column if not exists mode text not null default 'assigned',
  add column if not exists topic text, add column if not exists run_questions jsonb;
alter table public.training_runs drop constraint if exists training_runs_status_check;
alter table public.training_runs add constraint training_runs_status_check check (status in ('pending','running','done','abandoned'));
