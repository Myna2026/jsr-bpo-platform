-- =============================================================================
-- HR darf Management-Daten nicht sehen — Schnitt 1: Zeilen-Sperren           2026-08-05
-- =============================================================================
-- Bisher sahen management/hr (payslips zusätzlich finance) alles. Gefordert:
--   * HR sieht Gehälter/Bankdaten/Verträge/Resturlaub der MANAGEMENT-Personen NICHT.
--   * Management UND Finance sehen alles (Finance macht den Lohnlauf → braucht auch
--     die Management-Gehälter). Nur HR wird eingeschränkt.
-- „Admin" ist keine eigene Rolle → geschützt = Personen, deren app_users-Zugang
-- `management` trägt (Shkurte, Edi, Rajner, Thorsten, Betreiber; Master nur falls
-- mit employees-Zeile verknüpft).
--
-- DIESER SCHNITT: Tabellen, deren GANZE Zeile sensibel ist → Zeilen-Sperre.
--   payslips           voller Zugriff = management ODER finance; HR: außer geschützte.
--   employee_documents voller Zugriff = management;             HR: außer geschützte.
--                      (Finance hatte hier nie Zugriff — Verträge braucht Finance nicht,
--                       bleibt so.)
--   vacation_accounts  voller Zugriff = management;             HR: außer geschützte;
--                      Mitarbeiter: eigene. (Finance hatte hier nie Zugriff, bleibt so.)
--
-- NICHT hier (eigene Schnitte):
--   employees  → Spalten-Maskierung (Person bleibt sichtbar, nur Gehalt/Bank/Vertrag
--                null) via View + Frontend. Kostenbereiche für HR werden ausgeblendet
--                (statt teurer Summen-RPC).
--
-- Verbindung employees ↔ app_users über app_users.employee_id. is_admin()/
-- get_my_employee_id() existieren. Idempotent. Im Supabase SQL-Editor ausführen.
-- =============================================================================

-- ── Rollen-Helfer ────────────────────────────────────────────────────────────
create or replace function public.is_management()
returns boolean language sql stable security definer set search_path=public as $$
  select exists (select 1 from public.app_users where user_id=auth.uid() and role_keys && array['management']);
$$;
create or replace function public.is_finance()
returns boolean language sql stable security definer set search_path=public as $$
  select exists (select 1 from public.app_users where user_id=auth.uid() and role_keys && array['finance']);
$$;
create or replace function public.is_hr()
returns boolean language sql stable security definer set search_path=public as $$
  select exists (select 1 from public.app_users where user_id=auth.uid() and role_keys && array['hr']);
$$;

-- Gehört diese employees.id einem Management-Zugang? (= geschützte Person)
create or replace function public.is_protected_employee(emp uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists (select 1 from public.app_users where employee_id=emp and role_keys && array['management']);
$$;

revoke all    on function public.is_management()            from public;
revoke all    on function public.is_finance()               from public;
revoke all    on function public.is_hr()                    from public;
revoke all    on function public.is_protected_employee(uuid) from public;
grant execute on function public.is_management()            to authenticated;
grant execute on function public.is_finance()               to authenticated;
grant execute on function public.is_hr()                    to authenticated;
grant execute on function public.is_protected_employee(uuid) to authenticated;

-- Regel-Bausteine:
--   payslips:                     (is_management() OR is_finance()) OR (is_hr() AND NOT protected)
--   employee_documents / vacation: is_management()                  OR (is_hr() AND NOT protected)

-- ── payslips: bestehende Admin-Policy „HR full access payslips" (mgmt/hr/finance) ersetzen ──
-- Falls in der Diagnose weitere Admin-Policies auftauchen, ebenfalls droppen:
--   select policyname, cmd, qual from pg_policies where tablename='payslips';
drop policy if exists "HR full access payslips" on public.payslips;
drop policy if exists payslips_admin_all        on public.payslips;
drop policy if exists payslips_admin_select     on public.payslips;
drop policy if exists payslips_hr_all           on public.payslips;

create policy payslips_admin_all on public.payslips
  for all to authenticated
  using      ( public.is_management() or public.is_finance() or (public.is_hr() and not public.is_protected_employee(employee_id)) )
  with check ( public.is_management() or public.is_finance() or (public.is_hr() and not public.is_protected_employee(employee_id)) );

-- ── employee_documents: Admin-Policy ersetzen (kein Finance — Verträge) ──────
drop policy if exists employee_documents_admin_all on public.employee_documents;
create policy employee_documents_admin_all on public.employee_documents
  for all to authenticated
  using      ( public.is_management() or (public.is_hr() and not public.is_protected_employee(employee_id)) )
  with check ( public.is_management() or (public.is_hr() and not public.is_protected_employee(employee_id)) );

drop policy if exists "employee_docs admin all" on storage.objects;
create policy "employee_docs admin all" on storage.objects
  for all to authenticated
  using (
    bucket_id = 'employee-docs'
    and ( public.is_management() or (public.is_hr() and not public.is_protected_employee(((storage.foldername(name))[1])::uuid)) )
  )
  with check (
    bucket_id = 'employee-docs'
    and ( public.is_management() or (public.is_hr() and not public.is_protected_employee(((storage.foldername(name))[1])::uuid)) )
  );

-- ── vacation_accounts: Admin-Policies ersetzen (kein Finance) ────────────────
drop policy if exists va_select on public.vacation_accounts;
create policy va_select on public.vacation_accounts
  for select to authenticated
  using ( public.is_management()
          or (public.is_hr() and not public.is_protected_employee(employee_id))
          or employee_id = public.get_my_employee_id() );

drop policy if exists va_insert on public.vacation_accounts;
create policy va_insert on public.vacation_accounts
  for insert to authenticated
  with check ( public.is_management() or (public.is_hr() and not public.is_protected_employee(employee_id)) );

drop policy if exists va_update on public.vacation_accounts;
create policy va_update on public.vacation_accounts
  for update to authenticated
  using      ( public.is_management() or (public.is_hr() and not public.is_protected_employee(employee_id)) )
  with check ( public.is_management() or (public.is_hr() and not public.is_protected_employee(employee_id)) );

drop policy if exists va_delete on public.vacation_accounts;
create policy va_delete on public.vacation_accounts
  for delete to authenticated
  using ( public.is_management() or (public.is_hr() and not public.is_protected_employee(employee_id)) );

-- ── Prüfabfragen (optional) ──────────────────────────────────────────────────
-- select policyname, cmd from pg_policies where tablename in ('payslips','employee_documents','vacation_accounts');
-- select e.id, e.first_name, e.last_name, public.is_protected_employee(e.id) as geschuetzt from public.employees e order by geschuetzt desc;
