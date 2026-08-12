-- =============================================================================
-- Kundenportal-Archiv: Kunde liest NUR veröffentlichte Berichte des EIGENEN     2026-08-12
-- Projekts. Zugriff über REGELN (RLS), nicht nur Anzeige.
-- =============================================================================
-- Zuordnung ausschließlich über get_my_client_project_id() (aus 25e) — DIESELBE
-- Funktion wie alle anderen Kunden-Views (org_nodes, employees_client_view,
-- shifts_client_view, project_meta). KEINE zweite Zuordnungslogik.
--
-- Bestehende Policy presentations_mgmt_all (Management voll) bleibt. Diese Policy
-- ergänzt NUR den Kunden-Lesezugriff (SELECT). Policies werden ge-ODER-t:
--   * Management → presentations_mgmt_all → alles.
--   * Kunde (nicht Management) → NUR published=true UND eigenes Projekt.
--   * Alle anderen → keine der beiden greift → nichts (Deny-by-default).
--   * Entwürfe (published=false) sind für den Kunden NIE sichtbar.
-- Die Berichtszeile gehört ganz dem Kunden (eigener Bericht) → kein Spalten-
-- Masking nötig; die Zeilen-Regel IST der Zugriffsschutz. Kein Realtime für Kunden.
-- Idempotent. Im Supabase SQL-Editor ausführen.
-- =============================================================================

drop policy if exists presentations_client_read on public.presentations;
create policy presentations_client_read on public.presentations
  for select to authenticated
  using (
    published = true
    and project_id = public.get_my_client_project_id()
  );

-- ── Nachweis (mit dem HolidayCheck-Kundenzugang ausführen) ───────────────────
-- 1) Kunde sieht NUR eigene, veröffentlichte Berichte:
--      select count(*) from public.presentations;                     -- = Anzahl eigener published
--      select distinct project_id from public.presentations;          -- nur das eigene Projekt
-- 2) Fremdes Projekt / Entwürfe NICHT sichtbar:
--      select count(*) from public.presentations where published = false;   -- 0
--      select count(*) from public.presentations
--        where project_id <> public.get_my_client_project_id();             -- 0
-- 3) Als Management liefert der Zugriff weiter ALLE Berichte (published + Entwürfe).
