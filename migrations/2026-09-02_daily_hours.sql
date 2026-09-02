-- =============================================================================
-- Rohdaten statt Aggregate, Punkt 1 / Schnitt 1: Tagesebene der Stunden        2026-09-02
-- =============================================================================
-- Die Rohdaten-Excel (RohdatenImport) hat eine Zeile je Mitarbeiter je TAG (Pflichtspalte
-- Datum). Bisher summieren wir die Tage vor dem Speichern auf ISO-Wochen und legen nur
-- weekly_hours (kw/year) ab, die Tagesebene ist damit verloren. Ziel: die FEINSTE Ebene
-- (Tag) speichern, Aggregate (Woche) beim Lesen bilden.
--
-- Dieser Schnitt legt NUR die Tagestabelle an. Additiv, ändert nichts Bestehendes:
--   * weekly_hours bleibt unverändert Tabelle und Quelle (bis Schnitt 4 sie zur View macht).
--   * Kein Import schreibt hierher (das kommt in Schnitt 2, Dual-Write).
--
-- Grain: eine Zeile je project × employee × TAG. skill = Snapshot (welche Formel galt),
-- wie in weekly_hours. hours = Skill-Formel je Tag (Sales: E+BB+AS · Support: E+AQ), in
-- STUNDEN. pause_hours = Auftraggeber-Pausen des Tages. raw = Original-Sekunden je Spalte
-- des Tages (Nachvollzug / Re-Derive bei Formeländerung).
--
-- Zugriff: nur MANAGEMENT (is_management), identisch zu weekly_hours (Steuerungsmaterial,
-- keine Personalarbeit → HR/Kunde/MA sehen es NICHT).
-- Idempotent.
-- =============================================================================

create table if not exists public.daily_hours (
  id           uuid primary key default gen_random_uuid(),
  import_id    uuid references public.data_imports(id) on delete set null,
  project_id   text not null,
  employee_id  uuid not null references public.employees(id) on delete cascade,
  work_date    date not null,
  skill        text,
  hours        numeric,
  pause_hours  numeric,
  sales_calls  int,
  raw          jsonb,
  created_at   timestamptz not null default now()
);
-- Eine Zeile je project × employee × Tag (skill ist Snapshot, nicht Teil des Schlüssels —
-- wie bei weekly_hours). Re-Import eines Tages überschreibt (Delete je project/date + Insert
-- im Frontend, plus dieser Unique als Duplikat-Sperre).
create unique index if not exists uq_daily_hours on public.daily_hours(project_id, employee_id, work_date);
create index if not exists idx_daily_hours_scope on public.daily_hours(project_id, work_date);

alter table public.daily_hours enable row level security;
drop policy if exists daily_hours_mgmt on public.daily_hours;
create policy daily_hours_mgmt on public.daily_hours for all to authenticated
  using (public.is_management()) with check (public.is_management());
grant select, insert, update, delete on public.daily_hours to authenticated;
