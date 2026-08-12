-- =============================================================================
-- Call-Stichproben — Schnitt 6: Kunden-View (nur freigegebene Spalten)         2026-08-12
-- =============================================================================
-- Der Kunde sieht im Portal die Call-Qualität SEINES Projekts — je Skill. NUR die
-- Übersicht: Mitarbeitername, Prozent-Score, Datum, Projekt, Skill. KEINE internen
-- Kommentare (call_samples.note), KEINE Kriterien-Details (call_scores).
--
-- Umsetzung als SECURITY-DEFINER-View (läuft mit den Rechten des Owners, umgeht die
-- RLS der Basistabellen) mit fest eingebautem Projekt-Filter über get_my_client_project_id()
-- — dieselbe Kunde↔Projekt-Zuordnung wie alle anderen Kunden-Views, keine zweite Logik.
-- Der Kunde bekommt KEINEN Direktzugriff auf call_samples/call_scores (dort keine Kunden-
-- Policy) — nur diese View. Fremde Projekte sind ausgeschlossen (WHERE), interne Spalten
-- sind gar nicht Teil der View.
--
-- security_invoker AUS (Standard, hier explizit) ist entscheidend: mit invoker=ON würde
-- die (nicht vorhandene) Kunden-RLS greifen → 0 Zeilen. Idempotent. Im SQL-Editor ausführen.
-- =============================================================================

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
  s.year
from public.call_samples s
join public.employees e on e.id = s.employee_id
where s.status = 'done'
  and s.project_id = public.get_my_client_project_id();

-- Definer-Semantik erzwingen (nicht invoker) und nur freigegebenen Spalten-Zugriff geben.
alter view public.client_call_scores set (security_invoker = off);
revoke all on public.client_call_scores from anon;
grant select on public.client_call_scores to authenticated;

-- ── Nachweis (mit HolidayCheck-Zugang) ──────────────────────────────────────
--  • select * from public.client_call_scores  → nur HolidayCheck-Zeilen, keine note/comment-Spalten.
--  • Ein anderer Kunde sieht ausschließlich seine eigenen (get_my_client_project_id() differiert).
--  • select * from public.call_samples / public.call_scores  → als Kunde 0 Zeilen (keine Policy).
