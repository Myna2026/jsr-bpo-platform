-- =============================================================================
-- Call-Stichproben — Schnitt 1 (Bogen-Erweiterung): tristate + Hilfen + Punkt-Ampel  2026-08-12
-- =============================================================================
-- Anlass: echter HolidayCheck-Sales-Bogen. 15 Kriterien, je max 1 Punkt, ungewichtet,
-- DREISTUFIG (ja=1 / teilweise=0,5 / nein=0), „nicht anwendbar" = zählt wie ja.
-- Ampel in PUNKTEN (15–11 grün, 10,5–7 orange, ≤6,5 rot), nicht Prozent.
--
-- Änderungen (alle idempotent, additiv — keine bestehenden Spalten/Daten berührt):
--   1) Neuer Kriterientyp 'tristate' (CHECK erweitert in call_criteria + call_scores).
--   2) Je Kriterium: agent_hint (Hilfe für den Agenten) + level_hints jsonb {yes,partial,no}
--      (Auswerter-Ausprägungen). level_hints wird je Bewertung als Snapshot eingefroren.
--   3) Ampel in Einheiten: call_score_config.threshold_unit ('percent'|'points'), green_min/
--      yellow_min in dieser Einheit. Stichprobe führt total_points + max_points ECHT
--      (nicht in Prozent umgerechnet → Grenzen driften nicht bei Kriterien-Änderung).
--   4) Rückmeldungstexte je Ampelstufe (call_score_config.feedback_green/amber/red);
--      der zutreffende Text wird beim Speichern als call_samples.feedback_text eingefroren.
--      NUR HR + Mitarbeiter — der Kunde sieht Punkte, NICHT die Coaching-Texte.
--   5) Kunden-View client_call_scores um total_points + max_points erweitert (weiter ohne
--      Kommentare/Kriterien/feedback_text).
--
-- n.a. „zählt wie ja": Frontend schreibt bei n.a. volle Punkte, behält aber das na-Flag
-- (call_scores.na) für die Nachvollziehbarkeit. Kein DB-Zwang nötig.
-- Im Supabase SQL-Editor ausführen.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- §1  Kriterientyp 'tristate' zulassen (CHECK neu setzen — Inline-Constraint heißt
--     <tabelle>_<spalte>_check).
-- -----------------------------------------------------------------------------
alter table public.call_criteria drop constraint if exists call_criteria_type_check;
alter table public.call_criteria
  add constraint call_criteria_type_check check (type in ('points','yesno','tristate','grade'));

alter table public.call_scores drop constraint if exists call_scores_type_snapshot_check;
alter table public.call_scores
  add constraint call_scores_type_snapshot_check check (type_snapshot in ('points','yesno','tristate','grade'));

-- -----------------------------------------------------------------------------
-- §2  Neue Felder je Kriterium (+ Snapshot).
-- -----------------------------------------------------------------------------
alter table public.call_criteria add column if not exists agent_hint  text;   -- Hilfestellung für den Agenten
alter table public.call_criteria add column if not exists level_hints jsonb;   -- Auswerter-Ausprägungen {yes,partial,no}

alter table public.call_scores   add column if not exists level_hints_snapshot jsonb;  -- Ausprägungen zum Bewertungszeitpunkt

-- -----------------------------------------------------------------------------
-- §3  Stichprobe: Punkte ECHT führen (zusätzlich zu total_pct) + Rückmeldung einfrieren.
-- -----------------------------------------------------------------------------
alter table public.call_samples add column if not exists total_points  numeric;  -- erreichte Punkte
alter table public.call_samples add column if not exists max_points    numeric;  -- mögliche Punkte
alter table public.call_samples add column if not exists feedback_text text;      -- Rückmeldung der erreichten Ampelstufe (Snapshot, HR+MA)

-- -----------------------------------------------------------------------------
-- §4  Ampel-Config je Projekt/Skill: Einheit + Rückmeldungstexte.
--     green_min/yellow_min werden in threshold_unit interpretiert.
--     HolidayCheck Sales später: threshold_unit='points', green_min=11, yellow_min=7.
-- -----------------------------------------------------------------------------
alter table public.call_score_config add column if not exists threshold_unit text not null default 'percent';
alter table public.call_score_config drop constraint if exists call_score_config_threshold_unit_check;
alter table public.call_score_config
  add constraint call_score_config_threshold_unit_check check (threshold_unit in ('percent','points'));

alter table public.call_score_config add column if not exists feedback_green text;
alter table public.call_score_config add column if not exists feedback_amber text;
alter table public.call_score_config add column if not exists feedback_red   text;

-- -----------------------------------------------------------------------------
-- §5  Kunden-View: Punktzahl ergänzen (kein Coaching, keine Kriterien/Kommentare).
--     create or replace: bestehende Spalten in gleicher Reihenfolge, neue am ENDE.
-- -----------------------------------------------------------------------------
create or replace view public.client_call_scores as
select
  s.id,
  s.employee_id,
  trim(coalesce(e.first_name,'') || ' ' || coalesce(e.last_name,'')) as employee_name,
  s.project_id,
  s.skill,
  s.total_pct,
  s.sampled_date,
  s.kw,
  s.year,
  s.total_points,
  s.max_points
from public.call_samples s
join public.employees e on e.id = s.employee_id
where s.status = 'done'
  and s.project_id = public.get_my_client_project_id();

alter view public.client_call_scores set (security_invoker = off);
revoke all on public.client_call_scores from anon;
grant select on public.client_call_scores to authenticated;

-- -----------------------------------------------------------------------------
-- §6  Verifikation (auskommentiert)
-- -----------------------------------------------------------------------------
-- select conname, pg_get_constraintdef(oid) from pg_constraint
--   where conrelid='public.call_criteria'::regclass and conname='call_criteria_type_check'; -- enthält 'tristate'
-- select column_name from information_schema.columns
--   where table_name='call_samples' and column_name in ('total_points','max_points','feedback_text'); -- 3 Zeilen
-- select column_name from information_schema.columns
--   where table_name='call_score_config' and column_name like 'feedback_%' or column_name='threshold_unit';
