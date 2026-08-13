-- =============================================================================
-- Wochenbericht als Erweiterung von presentations (KEINE zweite Tabelle)     2026-08-13
-- =============================================================================
-- presentations kann bereits alles, was der Wochenbericht braucht: je Projekt/Skill/
-- Zeitraum, data-Snapshot (jsonb), published (Draft/veröffentlicht), public_token +
-- öffentliche RPC, Archiv, RLS is_management. Statt einer parallelen Fast-Dubletten-
-- Tabelle (weekly_reports) wird presentations minimal erweitert.
--
-- Lebenszyklus des Wochenberichts in presentations:
--   * kind = 'weekly'                 → Bericht ist ein Wochenbericht (vs. NULL = Ad-hoc).
--   * published = false               → „in Bearbeitung": Frontend rechnet LIVE aus den
--                                       Ablagen (weekly_hours/calls/gauges) + KPIs +
--                                       data.manual. data.snapshot ist NULL.
--   * published = true                → eingefroren: data.snapshot hält das assemblierte
--                                       Ergebnis inkl. Provenance. Spätere Uploads ändern
--                                       nichts mehr. Unpublish → snapshot verwerfen → live.
--
-- Konvention data (kind='weekly'):
--   data = {
--     manual:   { fte:{<employee_id>:num}, forecast:{<'YYYY-KW'>:num}, rueckmeldung:{…},
--                 massnahmen:"…", fehlzeiten_note:{<'YYYY-KW'>:"…"}, folie5:{…} },
--     snapshot: null | { …assembliertes Ergebnis + Provenance je Wert… }
--   }
--   Provenance je Wert: 'imported' (Ablage) | 'system' (KPI/berechnet) | 'manual' (Hand/Override).
--
-- report_fte bleibt eine EIGENE Tabelle: FTE-Standard je Mitarbeiter ist wiederverwendbare
-- Stammdaten (Fallback für jeden Bericht), kein Per-Bericht-Snapshot — wie kpi_config.
-- Der Per-Bericht-Override liegt in presentations.data.manual.fte.
--
-- Additiv/idempotent. Im Supabase SQL-Editor ausführen.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- §1  presentations um Discriminator + updated_at erweitern
-- -----------------------------------------------------------------------------
alter table public.presentations add column if not exists kind       text;          -- 'weekly' = Wochenbericht; NULL = Ad-hoc-Präsentation
alter table public.presentations add column if not exists updated_at timestamptz not null default now();

-- Ein aktiver Wochenbericht je Projekt × Skill × Zeitraum (verhindert Doppel-Drafts).
-- Nur für kind='weekly'; Ad-hoc-Präsentationen (kind NULL) bleiben mehrfach erlaubt.
create unique index if not exists uq_presentations_weekly
  on public.presentations (project_id, skill, period_year, period_no)
  where kind = 'weekly';

-- -----------------------------------------------------------------------------
-- §2  FTE-Standard je Mitarbeiter (Stammdaten, telefonie-only) — eigene Tabelle.
--     Fallback für jeden Wochenbericht; Per-Bericht-Override in data.manual.fte.
-- -----------------------------------------------------------------------------
create table if not exists public.report_fte (
  id           uuid primary key default gen_random_uuid(),
  project_id   text not null,
  employee_id  uuid not null references public.employees(id) on delete cascade,
  fte          numeric not null default 1,
  updated_by   uuid references auth.users(id) on delete set null,
  updated_at   timestamptz not null default now(),
  unique (project_id, employee_id)
);

alter table public.report_fte enable row level security;
drop policy if exists report_fte_mgmt on public.report_fte;
create policy report_fte_mgmt on public.report_fte for all to authenticated
  using (public.is_management()) with check (public.is_management());
grant select, insert, update, delete on public.report_fte to authenticated;
