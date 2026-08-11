-- =============================================================================
-- KPIs auf Projekt/Skill-Ebene: manuell erfasste Kundenwerte je Woche       2026-08-11
-- =============================================================================
-- Bisher: kpi_entries = Ist-Werte je MITARBEITER x KW (emp_id). Neu daneben: derselbe
-- Ablauf je PROJEKT+SKILL. Der Projekt/Skill-Wert ist ein vom KUNDEN genannter Mittelwert,
-- MANUELL eingetragen — NICHT aus den Mitarbeiterwerten abgeleitet.
--
-- Bewusst EIGENE Tabelle (nicht kpi_entries mit emp_id NULL): kpi_entries wird von
-- Performance/Ranking/Cockpit stark genutzt (emp_id FK, per-MA-Auswertung) — eine
-- Vermischung wäre riskant. Die DEFINITIONEN bleiben geteilt: KEINE zweite Config,
-- kpi_config (id, project_id, skill, name, unit, thresholds) wird unverändert weiter
-- verwendet; kpi_id hier referenziert denselben Slug.
--
-- Periodik = WÖCHENTLICH (kw, year), wie bei den Mitarbeitern.
-- RLS analog kpi_entries: lesen alle internen Rollen, schreiben Management/HR/Finance.
-- Idempotent. Im Supabase SQL-Editor ausführen.
-- =============================================================================

create table if not exists public.kpi_project_entries (
  id          uuid primary key default gen_random_uuid(),
  project_id  text not null,
  skill       text not null default '',      -- '' = projektweite KPI (kpi_config.skill NULL); sonst Skill-Key
  kw          int,
  year        int,
  kpi_id      text,                           -- Slug wie in kpi_config.id / kpi_entries.kpi_id
  value       numeric,                        -- vom Kunden genannter Wert (manuell)
  entered_by  text,
  ts          timestamptz default now()
);

-- Ein Wert je Projekt·Skill·Woche·KPI → Erfassung kann sauber upserten (onConflict).
create unique index if not exists kpi_project_entries_uniq
  on public.kpi_project_entries (project_id, skill, kw, year, kpi_id);
-- Cockpit-Lesezugriff (laufende/Vorwoche je Projekt).
create index if not exists idx_kpi_project_entries_lookup
  on public.kpi_project_entries (project_id, year, kw);

alter table public.kpi_project_entries enable row level security;

drop policy if exists "kpi_project_entries read internal" on public.kpi_project_entries;
create policy "kpi_project_entries read internal" on public.kpi_project_entries
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance','teamlead','projektleiter','mitarbeiter']));

drop policy if exists "kpi_project_entries HR write" on public.kpi_project_entries;
create policy "kpi_project_entries HR write" on public.kpi_project_entries
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));

grant select, insert, update, delete on public.kpi_project_entries to authenticated;

-- ── Verifikation (optional) ──────────────────────────────────────────────────
-- select count(*) from public.kpi_project_entries;                    -- 0 (leer)
-- select relrowsecurity from pg_class where relname='kpi_project_entries';  -- t
-- select polname from pg_policy where polrelid='public.kpi_project_entries'::regclass;  -- 2
