-- =============================================================================
-- Geburtsdatum: birthday date auf employees + cvs; Alter wird abgeleitet   2026-07-20
-- =============================================================================
-- Grund: `age` war manuell und veraltete. Kuenftig ist `birthday` die Quelle,
-- Alter wird berechnet (Frontend-Anzeige + Showcase serverseitig). Die alte
-- `age`-Spalte bleibt nullable als Fallback (kein manuelles Schreiben mehr).
--
-- `birthday` existierte bisher nur im Formular und wurde ins `extra`-jsonb geroutet
-- (beim Laden nicht zurueckgeflacht -> Datenverlust). Diese Migration macht daraus
-- echte Spalten und holt in `extra` liegende Werte einmalig heraus.
--
-- Idempotent (add column if not exists; Backfill nur wo extra den Key noch fuehrt;
-- create or replace function). Anzuwenden im Supabase SQL Editor (hier NICHT ausgefuehrt).
-- Voraussetzung: 25a_employees_supabase.sql, cvs_schema.sql.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1 Spalten
-- -----------------------------------------------------------------------------
alter table public.employees add column if not exists birthday date;
alter table public.cvs       add column if not exists birthday date;


-- -----------------------------------------------------------------------------
-- §2 Backfill aus extra (nur wo vorhanden), dann Key aus extra entfernen.
--    coalesce() ueberschreibt bestehende Spaltenwerte nicht; nicht-parsebare
--    Datumsstrings -> null (Regex-Guard fuer YYYY-MM-DD).
-- -----------------------------------------------------------------------------
update public.employees set
  birthday = coalesce(birthday, case when extra->>'birthday' ~ '^\d{4}-\d{2}-\d{2}$' then (extra->>'birthday')::date end),
  extra    = extra - 'birthday'
where extra ? 'birthday';

update public.cvs set
  birthday = coalesce(birthday, case when extra->>'birthday' ~ '^\d{4}-\d{2}-\d{2}$' then (extra->>'birthday')::date end),
  extra    = extra - 'birthday'
where extra ? 'birthday';


-- -----------------------------------------------------------------------------
-- §3 Showcase: cv_public_json liefert `age` aus birthday berechnet, Fallback age-Spalte.
--    `birthday` selbst bleibt AUS dem Objekt (nie in der Whitelist) -> Kunde sieht
--    nur das Alter, nicht das Geburtsdatum. Rest der Funktion unveraendert.
-- -----------------------------------------------------------------------------
create or replace function public.cv_public_json(c public.cvs, p_visible text[])
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object('id', c.id)
  || coalesce((
    select jsonb_object_agg(key, value)
    from jsonb_each(jsonb_build_object(
      'first_name',       c.first_name,
      'last_name',        c.last_name,
      'age',              coalesce(extract(year from age(c.birthday))::int, c.age),
      'gender',           c.gender,
      'city',             c.city,
      'dialect',          c.dialect,
      'education',        c.education,
      'education_level',  c.education_level,
      'experience_years', c.experience_years,
      'work_history',     c.work_history,
      'language_level',   c.language_level,
      'writing_level',    c.writing_level,
      'languages_str',    c.languages_str,
      'homeoffice_pref',  c.homeoffice_pref,
      'available_from',   c.available_from,
      'dream',            c.dream,
      'travel_wish',      c.travel_wish,
      'hobbies',          c.hobbies,
      'favorite_food',    c.favorite_food,
      'photo_url',        c.photo_url,
      'photo_color',      c.photo_color,
      'audios',           c.audios,
      'videos',           c.videos,
      'test_scores',      c.test_scores
    ))
    where key = any(coalesce(p_visible, '{}'::text[]))   -- HR-Auswahl nimmt nur weg
  ), '{}'::jsonb);
$$;
revoke all on function public.cv_public_json(public.cvs, text[]) from public;


-- =============================================================================
-- Verifikation (auskommentiert)
-- =============================================================================
-- (a) Spalten:
--     select table_name, column_name, data_type from information_schema.columns
--      where table_schema='public' and column_name='birthday'
--        and table_name in ('employees','cvs');
-- (b) Kein birthday mehr in extra:
--     select count(*) from public.employees where extra ? 'birthday';   -- 0
--     select count(*) from public.cvs       where extra ? 'birthday';   -- 0
-- (c) age-Berechnung greift (Beispiel):
--     select first_name, birthday, extract(year from age(birthday))::int as age_calc
--       from public.cvs where birthday is not null limit 5;
-- =============================================================================
