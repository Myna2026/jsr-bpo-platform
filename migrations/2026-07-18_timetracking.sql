-- =============================================================================
-- Zeiterfassung: localStorage (jsr_time_v1) -> Supabase   2026-07-18
-- =============================================================================
-- Etappe Z1: NUR SCHEMA + RLS. Noch NICHT im Frontend verdrahtet (eigene Etappe).
--   time_sessions = 1 Row pro Stempel-Session (Clock-in/out, Pausen, Raucherpausen)
--
-- Felder 1:1 aus der jsr_time_v1-Session (hr.html TimeTracking, clock-in 16613 +
-- clock-out 16630): Zeiten als 'HH:MM'-Strings -> text (der Frontend-Wert ist
-- minutengenau ohne Sekunden). pauses/smokes sind Arrays {start,end,duration}
-- -> jsonb. emp_id = uuid -> FK auf employees(id), on delete cascade.
--
-- RLS nach kpi_entries-Muster (siehe 2026-07-18_kpi_self_read.sql):
--   1) "read internal" -> management/hr/finance/teamlead/projektleiter (KEIN mitarbeiter)
--   2) "self read"     -> emp_id = eigene employee_id via app_users (ungated Self-SELECT)
--   3) "HR write"      -> management/hr/finance (FOR ALL)
--
-- Idempotent (create table / index / policy IF (NOT) EXISTS + drop policy if exists).
-- Anzuwenden im Supabase SQL Editor (hier NICHT ausgefuehrt).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1 Tabelle
-- -----------------------------------------------------------------------------
create table if not exists public.time_sessions (
  id            uuid primary key default gen_random_uuid(),
  emp_id        uuid references public.employees(id) on delete cascade,
  session_date  date,                          -- Frontend: 'date' ('YYYY-MM-DD')
  clock_in      text,                           -- 'HH:MM'
  clock_out     text,                           -- 'HH:MM' oder null (laufende Session)
  hours         numeric,                        -- Netto-Stunden (1 Nachkommastelle)
  hours_gross   numeric,                        -- Brutto-Stunden (vor Pausenabzug)
  pauses        jsonb default '[]'::jsonb,      -- [{start,end,duration(min)}]
  smokes        jsonb default '[]'::jsonb,      -- [{start,end,duration(min)}]
  pause_active  text,                           -- Startzeit laufender Pause oder null
  smoke_active  text,                           -- Startzeit laufender Raucherpause oder null
  pause_total   integer,                        -- Summe Pausenminuten (bei clock-out)
  smoke_total   integer,                        -- Summe Raucherpausenminuten (bei clock-out)
  created_at    timestamptz default now()
);
create index if not exists idx_time_sessions_emp_date on public.time_sessions(emp_id, session_date);


-- -----------------------------------------------------------------------------
-- §2 RLS — read internal (ohne mitarbeiter) + self read + HR write
-- -----------------------------------------------------------------------------
alter table public.time_sessions enable row level security;
drop policy if exists "time_sessions read all authenticated" on public.time_sessions;
drop policy if exists "time_sessions read internal" on public.time_sessions;
drop policy if exists "time_sessions self read" on public.time_sessions;
drop policy if exists "time_sessions HR write" on public.time_sessions;

-- (1) Interne Rollen OHNE 'mitarbeiter' -> voller Lesezugriff auf alle Zeilen.
create policy "time_sessions read internal" on public.time_sessions
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance','teamlead','projektleiter']));

-- (2) Self-SELECT: jede/r sieht NUR eigene Zeilen (emp_id = eigene employee_id).
create policy "time_sessions self read" on public.time_sessions
  for select to authenticated
  using (emp_id = (select employee_id from app_users where user_id = auth.uid()));

-- (3) Schreiben nur management/hr/finance.
create policy "time_sessions HR write" on public.time_sessions
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));


-- =============================================================================
-- Verifikation (auskommentiert)
-- =============================================================================
-- (a) Tabelle + Spalten (erwartet 14):
--     select count(*) from information_schema.columns
--      where table_schema='public' and table_name='time_sessions';   -- 14
-- (b) RLS + 3 Policies:
--     select c.relname, count(p.polname) from pg_class c
--      left join pg_policy p on p.polrelid=c.oid
--      where c.relname='time_sessions' group by c.relname;            -- 3
-- (c) FK emp_id -> employees(id), on delete cascade:
--     select conname, confdeltype from pg_constraint
--      where conrelid='public.time_sessions'::regclass and contype='f';  -- confdeltype='c'
-- =============================================================================
