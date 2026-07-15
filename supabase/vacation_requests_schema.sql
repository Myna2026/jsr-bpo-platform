-- ============================================================================
-- TIVE 360° — Urlaubsanträge auf Supabase (Go-Live-Blocker 2)
-- Einfügen im Supabase SQL Editor. Idempotent (kann erneut ausgeführt werden).
--
-- Ersetzt localStorage jsr_vacation_requests_v1 (per-Device, cross-subdomain tot).
-- Vorher: MA reicht auf mitarbeiter.tive360.de ein, HR liest auf hr.tive360.de —
-- getrennter Speicher, Antrag kam nie an. Jetzt geteilte Tabelle + RLS + Realtime.
--
-- Prädikate 1:1 aus den Bestands-Migrationen:
--   HR-Vollzugriff = ('management','hr','finance')  (wie 25a/cvs)
--   auth.uid() → Mitarbeiter über app_users.employee_id (Fallback staff_number)
-- ============================================================================

create extension if not exists pgcrypto;


-- ----------------------------------------------------------------------------
-- 1) get_my_employee_id() — auth.uid() → eigene employees.id.
--    Primär app_users.employee_id, Fallback staff_number (spiegelt die Auflösung
--    in mitarbeiter.html: loadOwnEmployeeFromDB employee_id → staff_number).
-- ----------------------------------------------------------------------------
create or replace function public.get_my_employee_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select employee_id from public.app_users where user_id = auth.uid()),
    (select e.id from public.employees e
       join public.app_users au on au.user_id = auth.uid()
       where au.staff_number is not null and e.staff_number = au.staff_number
       limit 1)
  );
$$;
revoke all    on function public.get_my_employee_id() from public;
grant execute on function public.get_my_employee_id() to authenticated;


-- ----------------------------------------------------------------------------
-- 2) vacation_requests — ein Antrag. employee_name denormalisiert (Snapshot,
--    überlebt einen gelöschten/umbenannten MA). Absence-Erzeugung bei Genehmigung
--    passiert NICHT hier, sondern im Frontend an employees.absences (Block 1).
-- ----------------------------------------------------------------------------
create table if not exists public.vacation_requests (
  id            uuid primary key default gen_random_uuid(),
  employee_id   uuid not null,
  employee_name text,
  from_date     date not null,
  to_date       date not null,
  type          text not null default 'vacation' check (type in ('vacation','unpaid')),
  days          numeric not null default 0,
  status        text not null default 'pending'  check (status in ('pending','approved','rejected')),
  note          text,
  reject_reason text,
  approved_by   text,
  created_at    timestamptz default now()
);
create index if not exists idx_vacreq_employee on public.vacation_requests(employee_id);
create index if not exists idx_vacreq_status   on public.vacation_requests(status);


-- ----------------------------------------------------------------------------
-- 3) RLS: MA sieht/reicht nur eigene ein, HR sieht/entscheidet alle.
--    Mehrere permissive SELECT-Policies werden mit OR kombiniert.
-- ----------------------------------------------------------------------------
alter table public.vacation_requests enable row level security;

-- MA: eigene lesen
drop policy if exists "vacreq MA select own" on public.vacation_requests;
create policy "vacreq MA select own" on public.vacation_requests
  for select to authenticated
  using (employee_id = public.get_my_employee_id());

-- MA: eigene einreichen (immer als pending; kein Selbst-Genehmigen)
drop policy if exists "vacreq MA insert own" on public.vacation_requests;
create policy "vacreq MA insert own" on public.vacation_requests
  for insert to authenticated
  with check (employee_id = public.get_my_employee_id() and status = 'pending');

-- HR: alle lesen
drop policy if exists "vacreq HR select all" on public.vacation_requests;
create policy "vacreq HR select all" on public.vacation_requests
  for select to authenticated
  using (exists (select 1 from public.app_users
    where user_id = auth.uid() and role_keys && array['management','hr','finance']::text[]));

-- MA: eigene, noch offene Anträge zurückziehen
drop policy if exists "vacreq MA delete own pending" on public.vacation_requests;
create policy "vacreq MA delete own pending" on public.vacation_requests
  for delete to authenticated
  using (employee_id = public.get_my_employee_id() and status = 'pending');

-- HR: entscheiden (Status/Grund setzen)
drop policy if exists "vacreq HR update" on public.vacation_requests;
create policy "vacreq HR update" on public.vacation_requests
  for update to authenticated
  using (exists (select 1 from public.app_users
    where user_id = auth.uid() and role_keys && array['management','hr','finance']::text[]))
  with check (exists (select 1 from public.app_users
    where user_id = auth.uid() and role_keys && array['management','hr','finance']::text[]));


-- ----------------------------------------------------------------------------
-- 4) Realtime-Publication (sonst kein Live-Eingang bei HR). Idempotent.
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname='supabase_realtime' and schemaname='public' and tablename='vacation_requests') then
    alter publication supabase_realtime add table public.vacation_requests;
  end if;
end $$;


-- ============================================================================
-- FERTIG. Danach Frontend: mitarbeiter.html submitVacationRequest → insert +
-- Reads → select; hr.html VacationRequestsView → Load/Realtime + updateRequest
-- (erst Absence via saveEmployeeToDB, dann status='approved').
-- ============================================================================
