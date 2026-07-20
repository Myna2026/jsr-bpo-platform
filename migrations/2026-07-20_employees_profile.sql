-- =============================================================================
-- employees: Steckbrief-/Profil-Spalten (analog cvs)                  2026-07-20
-- =============================================================================
-- Zweck: Der Kandidaten-Steckbrief (cvs) soll lueckenlos zum Mitarbeiter uebergehen.
-- Bisher landeten diese Felder auf employees im `extra`-jsonb-Catch-all (weil keine
-- Spalten existierten) und wurden beim Laden nicht flach zurueckgespreadet -> faktisch
-- unsichtbar. Diese Migration legt echte Spalten an (Typen wie in cvs) und holt bereits
-- in `extra` liegende Werte einmalig heraus.
--
-- `city` existiert bereits als employees-Spalte (in EMP_COLS) -> ADD IF NOT EXISTS ist
-- dort ein No-Op. Die uebrigen 12 Felder sind neu.
--
-- Idempotent: ADD COLUMN IF NOT EXISTS + Backfill nur dort, wo `extra` den Key noch
-- fuehrt (nach Lauf ist der Key aus `extra` entfernt -> Re-Run trifft nichts).
-- Anzuwenden im Supabase SQL Editor (hier NICHT ausgefuehrt).
-- Voraussetzung: 25a_employees_supabase.sql (employees + extra jsonb).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1 Spalten (Typen 1:1 wie cvs: age/experience_years integer, Rest text)
-- -----------------------------------------------------------------------------
alter table public.employees add column if not exists age              integer;
alter table public.employees add column if not exists gender           text;
alter table public.employees add column if not exists city             text;   -- meist schon vorhanden
alter table public.employees add column if not exists education        text;
alter table public.employees add column if not exists education_level  text;
alter table public.employees add column if not exists experience_years integer;
alter table public.employees add column if not exists language_level   text;
alter table public.employees add column if not exists writing_level    text;
alter table public.employees add column if not exists languages_str    text;
alter table public.employees add column if not exists dream            text;
alter table public.employees add column if not exists hobbies          text;
alter table public.employees add column if not exists favorite_food    text;
alter table public.employees add column if not exists travel_wish      text;


-- -----------------------------------------------------------------------------
-- §2 Einmaliger Backfill: Werte aus `extra` in die neuen Spalten ziehen und aus
--    `extra` entfernen. coalesce() ueberschreibt bestehende Spaltenwerte nicht.
--    Integer-Felder defensiv per Regex gecastet (nicht-numerische Reste -> null).
-- -----------------------------------------------------------------------------
update public.employees set
  age              = coalesce(age,              case when extra->>'age' ~ '^\s*[0-9]+\s*$' then trim(extra->>'age')::int end),
  gender           = coalesce(gender,           nullif(extra->>'gender','')),
  education        = coalesce(education,         nullif(extra->>'education','')),
  education_level  = coalesce(education_level,   nullif(extra->>'education_level','')),
  experience_years = coalesce(experience_years, case when extra->>'experience_years' ~ '^\s*[0-9]+\s*$' then trim(extra->>'experience_years')::int end),
  language_level   = coalesce(language_level,    nullif(extra->>'language_level','')),
  writing_level    = coalesce(writing_level,     nullif(extra->>'writing_level','')),
  languages_str    = coalesce(languages_str,     nullif(extra->>'languages_str','')),
  dream            = coalesce(dream,             nullif(extra->>'dream','')),
  hobbies          = coalesce(hobbies,           nullif(extra->>'hobbies','')),
  favorite_food    = coalesce(favorite_food,     nullif(extra->>'favorite_food','')),
  travel_wish      = coalesce(travel_wish,       nullif(extra->>'travel_wish','')),
  extra = extra - 'age' - 'gender' - 'education' - 'education_level' - 'experience_years'
                - 'language_level' - 'writing_level' - 'languages_str' - 'dream'
                - 'hobbies' - 'favorite_food' - 'travel_wish'
where extra ?| array['age','gender','education','education_level','experience_years',
                     'language_level','writing_level','languages_str','dream',
                     'hobbies','favorite_food','travel_wish'];


-- =============================================================================
-- Verifikation (auskommentiert)
-- =============================================================================
-- (a) Alle 13 Spalten vorhanden:
--     select column_name, data_type from information_schema.columns
--      where table_schema='public' and table_name='employees'
--        and column_name in ('age','gender','city','education','education_level',
--          'experience_years','language_level','writing_level','languages_str',
--          'dream','hobbies','favorite_food','travel_wish') order by column_name;
-- (b) Keine dieser Keys mehr in extra:
--     select count(*) from public.employees
--      where extra ?| array['age','gender','education','dream','travel_wish'];   -- 0
-- =============================================================================
