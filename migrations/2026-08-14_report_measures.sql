-- =============================================================================
-- Maßnahmen-Nachverfolgung (fortlaufend über Wochen)                         2026-08-14
-- =============================================================================
-- Bis zu 5 Maßnahmen je Woche werden beim Kundentermin erfasst. Offene Maßnahmen WANDERN
-- automatisch in den Bericht der Folgewoche, bis sie erledigt sind (Nachverfolgung statt
-- Momentaufnahme). Bewertung je Maßnahme: open (rot) | in_progress (gelb) | done (grün) + Kommentar.
--
-- Eigene Tabelle (NICHT im presentations.data-Snapshot), weil die Maßnahmen ueber die Wochen
-- hinweg leben — ein Per-Woche-Snapshot koennte das nicht.
--
-- Carry-over-Regel im Frontend: Ein Bericht (project,skill,kw,year) zeigt alle Maßnahmen mit
--   status <> 'done'  ODER  (done_year=year AND done_kw=kw)   -- in der Woche erledigte noch sichtbar.
--
-- Zugriff nur MANAGEMENT (is_management). Additiv/idempotent. Im Supabase SQL-Editor ausfuehren.
-- =============================================================================
create table if not exists public.report_measures (
  id              uuid primary key default gen_random_uuid(),
  project_id      text not null,
  skill           text not null default 'sales',
  text            text not null,                         -- die Maßnahme
  status          text not null default 'open' check (status in ('open','in_progress','done')),
  comment         text,
  created_year    int not null,                          -- Woche der Erfassung
  created_kw      int not null,
  done_year       int,                                   -- Woche der Erledigung (Historie)
  done_kw         int,
  seq             int not null default 0,
  created_by      uuid references auth.users(id) on delete set null,
  created_by_name text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists idx_report_measures_scope on public.report_measures(project_id, skill, status, created_year, created_kw);

alter table public.report_measures enable row level security;
drop policy if exists report_measures_mgmt on public.report_measures;
create policy report_measures_mgmt on public.report_measures for all to authenticated
  using (public.is_management()) with check (public.is_management());
grant select, insert, update, delete on public.report_measures to authenticated;
