-- =============================================================================
-- employees: Verfuegbarkeits-/Planungs-Spalten                        2026-07-20
-- =============================================================================
-- Zweck: Sieben operative Planungsfelder aus dem EmployeeModal hatten bisher keine
-- echte employees-Spalte und liefen ueber das `extra`-jsonb-Catch-all. Sie round-
-- trippen zwar (empWithExtra spreadet extra flach zurueck), sind aber fachlich
-- erstklassige Schicht-Constraints (harte Regeln im Workforce-/KI-Planer:
-- work_weekend/work_holidays), keine "unbekannten Reste". `extra` ist laut 25a nur
-- Sammelbecken fuer wirklich Unbekanntes → diese Felder bekommen echte Spalten.
--
-- Booleans: work_weekend/holidays/saturday/sunday/split. Das Frontend fuehrt sie
-- gemischt als 'yes'/'no' (Select) und true/false (Import/Seed); die Save-Coercion
-- normalisiert kuenftig auf boolean. Der Backfill unten deckt beide Alt-Formen ab.
-- Text: work_notes (freier Planungshinweis), training_id (Schulungs-Zuordnung;
-- bewusst text, nicht uuid — die Frontend-IDs sind nicht garantiert UUIDs).
--
-- Idempotent: ADD COLUMN IF NOT EXISTS + Backfill nur dort, wo `extra` den Key noch
-- fuehrt (coalesce ueberschreibt bestehende Spaltenwerte nie; nach Lauf ist der Key
-- aus `extra` entfernt → Re-Run trifft nichts).
-- Anzuwenden im Supabase SQL Editor (hier NICHT ausgefuehrt).
-- Voraussetzung: 25a_employees_supabase.sql (employees + extra jsonb).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1 Spalten
-- -----------------------------------------------------------------------------
alter table public.employees add column if not exists work_weekend   boolean;
alter table public.employees add column if not exists work_holidays  boolean;
alter table public.employees add column if not exists work_saturday  boolean;
alter table public.employees add column if not exists work_sunday    boolean;
alter table public.employees add column if not exists work_split     boolean;
alter table public.employees add column if not exists work_notes     text;
alter table public.employees add column if not exists training_id    text;


-- -----------------------------------------------------------------------------
-- §2 Backfill aus extra (nur wo vorhanden), dann Keys aus extra entfernen.
--    Booleans: 'yes'/'ja'/'true'/'1'/'t' → true, jeder andere gesetzte Wert → false,
--    fehlender Key → null. coalesce() schuetzt bereits gesetzte Spaltenwerte.
-- -----------------------------------------------------------------------------
update public.employees set
  work_weekend  = coalesce(work_weekend,  case when extra ? 'work_weekend'  then lower(extra->>'work_weekend')  in ('yes','ja','true','1','t') end),
  work_holidays = coalesce(work_holidays, case when extra ? 'work_holidays' then lower(extra->>'work_holidays') in ('yes','ja','true','1','t') end),
  work_saturday = coalesce(work_saturday, case when extra ? 'work_saturday' then lower(extra->>'work_saturday') in ('yes','ja','true','1','t') end),
  work_sunday   = coalesce(work_sunday,   case when extra ? 'work_sunday'   then lower(extra->>'work_sunday')   in ('yes','ja','true','1','t') end),
  work_split    = coalesce(work_split,    case when extra ? 'work_split'    then lower(extra->>'work_split')    in ('yes','ja','true','1','t') end),
  work_notes    = coalesce(work_notes,    nullif(extra->>'work_notes', '')),
  training_id   = coalesce(training_id,   nullif(extra->>'training_id', '')),
  extra = extra - 'work_weekend' - 'work_holidays' - 'work_saturday' - 'work_sunday' - 'work_split' - 'work_notes' - 'training_id'
where extra ?| array['work_weekend','work_holidays','work_saturday','work_sunday','work_split','work_notes','training_id'];


-- =============================================================================
-- Verifikation (auskommentiert)
-- =============================================================================
-- (a) Spalten:
--     select column_name, data_type from information_schema.columns
--      where table_schema='public' and table_name='employees'
--        and column_name in ('work_weekend','work_holidays','work_saturday',
--                            'work_sunday','work_split','work_notes','training_id');
-- (b) Keine der 7 Keys mehr in extra:
--     select count(*) from public.employees
--      where extra ?| array['work_weekend','work_holidays','work_saturday',
--                           'work_sunday','work_split','work_notes','training_id'];  -- 0
-- =============================================================================
