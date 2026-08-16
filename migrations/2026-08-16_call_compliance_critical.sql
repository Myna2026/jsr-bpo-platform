-- =============================================================================
-- Call-Qualität: Compliance-kritische Kriterien (Schnitt 1 — Datenmodell)
-- =============================================================================
-- Kontext: HolidayCheck-Support-Bogen. Ein als "compliance_critical" markiertes
-- Kriterium (z.B. Datenabgleich) hat KEINE Teilweise-Stufe (nur ja/nein, kein
-- n.a.). Bei Bewertung "nein" faellt der GESAMTE Call auf 0 Punkte — unabhaengig
-- von allen anderen Kriterien.
--
-- Zwei getrennte Achsen (bewusst, siehe Diskussion):
--   * total_points/total_pct  = offizieller Call-Score. Bei Verstoss = 0 (der
--                               Call ist genullt; Kunde/Archiv sehen 0 + Grund).
--   * raw_points              = fachliche Punktzahl OHNE Nullung. Auf JEDER
--                               Stichprobe gefuellt (bei Verstoss != total_points,
--                               sonst identisch). Ø/Rangliste rechnen hierueber,
--                               damit ein fachlich starker Agent mit einem
--                               Verstoss nicht ans Ende rutscht.
--   * compliance_failed       = Verstoss ja/nein. Wird SEPARAT gezaehlt/angezeigt,
--                               nicht im Score versteckt.
--
-- Alle Spalten werden additiv angelegt. Score-Nullung + raw_points passieren
-- beim Speichern im Frontend (Schnitt 2) und werden — wie total_points heute —
-- eingefroren. Diese Migration legt nur die Struktur.
-- Additiv + idempotent, keine Datenmigration noetig (Greenfield/Dummy).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- §1  Kennzeichen am Kriterium + Snapshot je Bewertung
-- -----------------------------------------------------------------------------
-- Generisch: JEDES Kriterium kann compliance-kritisch sein (nicht hart auf
-- "Datenabgleich" verdrahtet). Der Snapshot friert den Regel-Stand je Stichprobe
-- ein — aendert HR das Kennzeichen spaeter, bleiben Altbewertungen korrekt.
alter table public.call_criteria
  add column if not exists compliance_critical boolean not null default false;

alter table public.call_scores
  add column if not exists compliance_critical_snapshot boolean not null default false;

-- -----------------------------------------------------------------------------
-- §2  Stichprobe: Verstoss-Flag + fachliche Rohpunkte
-- -----------------------------------------------------------------------------
alter table public.call_samples
  add column if not exists compliance_failed boolean not null default false;

-- Fachliche Punktzahl ohne Compliance-Nullung. Wird vom Frontend auf JEDER
-- Stichprobe gesetzt (= total_points, wenn kein Verstoss). Nullable, damit
-- Alt-Stichproben ohne den Wert nicht brechen; Auswertungen nehmen dort
-- COALESCE(raw_points, total_points).
alter table public.call_samples
  add column if not exists raw_points numeric;

-- -----------------------------------------------------------------------------
-- §3  Kunden-View: Verstoss + Rohpunkte ergaenzen (weiter kein Coaching/Kriterien)
--     create or replace: bestehende Spalten in gleicher Reihenfolge, neue am ENDE.
--     Der Kunde soll die 0 als Compliance-Thema erkennen (sonst unerklaerlich)
--     und die fachliche Leistung dahinter sehen.
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
  s.max_points,
  s.raw_points,
  s.compliance_failed
from public.call_samples s
join public.employees e on e.id = s.employee_id
where s.status = 'done'
  and s.project_id = public.get_my_client_project_id();

alter view public.client_call_scores set (security_invoker = off);
revoke all on public.client_call_scores from anon;
grant select on public.client_call_scores to authenticated;

-- -----------------------------------------------------------------------------
-- §4  Verifikation (auskommentiert)
-- -----------------------------------------------------------------------------
-- select column_name from information_schema.columns
--   where table_name='call_criteria' and column_name='compliance_critical';               -- 1 Zeile
-- select column_name from information_schema.columns
--   where table_name='call_samples' and column_name in ('compliance_failed','raw_points'); -- 2 Zeilen
-- select column_name from information_schema.columns
--   where table_name='call_scores' and column_name='compliance_critical_snapshot';         -- 1 Zeile
-- select count(*) from client_call_scores;   -- als Kunde: eigene Calls, jetzt mit raw_points/compliance_failed
