-- Arbeitsverteilungs-System, Schnitt 1: Datenmodell + RLS (rein ADDITIV, drei neue Tabellen).
-- daily_tasks_done bleibt HIER unangetastet (Instanz-Koernung folgt in Schnitt 2 gemeinsam mit dem
-- Frontend-Umbau, sonst braeche das aktuelle Abhaken im Fenster zwischen den Schnitten).
-- Helfer aus schema_auth.sql: is_management() (management), is_planner() (management/hr/teamlead/projektleiter),
-- get_my_employee_project_id(). PG17 -> UNIQUE NULLS NOT DISTINCT verfuegbar.

-- 1) task_assignments: Overlay je Zugang ueber den Rollen-Katalog (ROLE_TASKS). Eine Zeile pro
--    (Nutzer, Aufgabe, Projekt): active=false = Katalog-Aufgabe fuer den Nutzer entfernt; project_id
--    null = projektuebergreifend. Effektive Liste (Rolle +/- Overlay) rechnet das Frontend in Schnitt 2.
create table if not exists public.task_assignments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  task_key text not null,
  project_id text,
  active boolean not null default true,
  cadence_override text,
  note text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint task_assignments_uniq unique nulls not distinct (user_id, task_key, project_id)
);
alter table public.task_assignments enable row level security;
create policy task_assignments_sel on public.task_assignments
  for select to authenticated using (is_planner());
create policy task_assignments_write on public.task_assignments
  for all to authenticated using (is_management()) with check (is_management());
grant select, insert, update, delete on public.task_assignments to authenticated;

-- 2) task_snooze: Sperrbildschirm-Verschiebung. Genau eine aktive Verschiebung je Instanz und Tag.
--    Rein nutzereigen.
create table if not exists public.task_snooze (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  task_key text not null,
  project_id text,
  date date not null,
  snooze_until timestamptz not null,
  created_at timestamptz not null default now(),
  constraint task_snooze_uniq unique nulls not distinct (user_id, task_key, project_id, date)
);
alter table public.task_snooze enable row level security;
create policy task_snooze_own on public.task_snooze
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update, delete on public.task_snooze to authenticated;

-- 3) task_takeover: Vertretung ("uebernehmen, dann abhaken"). Eine aktive Uebernahme je Instanz und Tag;
--    orig_assignee = urspruenglich Zustaendiger, taken_over_by = Eingesprungener. Schreiben spaeter ueber
--    SECURITY-DEFINER-RPC (Berechtigung: selbes Projekt / Management / Hierarchie) in Schnitt 2 -> hier
--    KEIN direktes Insert/Update-Policy, nur Lesen fuer die Uebersicht.
create table if not exists public.task_takeover (
  id uuid primary key default gen_random_uuid(),
  task_key text not null,
  project_id text,
  date date not null,
  orig_assignee uuid,
  taken_over_by uuid not null references auth.users(id) on delete cascade,
  taken_over_at timestamptz not null default now(),
  constraint task_takeover_uniq unique nulls not distinct (task_key, project_id, date)
);
alter table public.task_takeover enable row level security;
create policy task_takeover_sel on public.task_takeover
  for select to authenticated using (is_planner());
grant select on public.task_takeover to authenticated;
