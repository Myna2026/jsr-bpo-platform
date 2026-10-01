-- HolidayCheck bezahlt grundsaetzlich nur die Stunden, die im Forecast stehen: verguetet wird der
-- kleinere Wert aus Forecast und geliefert (Klarstellung Shkurte, 2026-10-01). Ausnahme sind Stunden,
-- die HolidayCheck zusaetzlich angefordert hat oder die wegen des tatsaechlichen Bedarfs noetig waren.
-- Im Monatsblatt des Auftraggebers ("Rueckmeldung Monatsebene") stehen diese Stunden nur versteckt:
-- die handgetippte Spalte "Vergutet" ist Forecast PLUS Zusatzstunden, die Zusatzstunden sind also
-- die Differenz zum Forecast. Das liegt erst nach dem Monat vor und ist nicht beschriftet; die
-- Spalte "Zusatzinformationen" meint laut Kommentar im Blatt die Planannahmen, nicht Zusatzstunden.
-- Deshalb wird hier tagesaktuell gepflegt: je Tag und Skill die Stunden plus Begruendung und Herkunft.
create table if not exists hc_extra_hours (
  id          uuid primary key default gen_random_uuid(),
  project_id  text not null,
  skill       text not null,
  work_date   date not null,
  hours       numeric(6,2) not null check (hours > 0),
  reason      text,
  source      text not null default 'hc_anforderung',   -- hc_anforderung | bedarf
  created_by  uuid,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (project_id, skill, work_date)
);
create index if not exists hc_extra_hours_tag on hc_extra_hours(project_id, work_date);

alter table hc_extra_hours enable row level security;
drop policy if exists "hc_extra_hours read" on hc_extra_hours;
create policy "hc_extra_hours read" on hc_extra_hours for select using (is_planner());
drop policy if exists "hc_extra_hours write" on hc_extra_hours;
create policy "hc_extra_hours write" on hc_extra_hours for all
  using (is_management() or (is_planner() and project_id = get_my_employee_project_id()))
  with check (is_management() or (is_planner() and project_id = get_my_employee_project_id()));
