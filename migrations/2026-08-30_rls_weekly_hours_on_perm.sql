-- Zurückgestellte Tabellen, Block 2: weekly_hours (importierte Roh-Stunden) aufs Modell. Heimat = Schichten & Zeit
-- (Bereich 'shift'), aber mit hr-NUANCE: IST = Management + Planer-eigenes-Projekt, KEIN hr/finance/self. Der
-- shift-Seed gäbe hr aber alles (shift hr=edit/all) → ohne Nuance spränge hr von 0 auf alle Stunden. Darum
-- `NOT is_hr()` in der Policy (finance ist über shift-Seed mode=none ohnehin draußen). Skill bewusst NULL (wie bei
-- Schichten, Basis-RLS skill-scopt nie). Verifiziert IST-exakt: mgmt/leads=148, hr=0, finance/mitarbeiter=0.

begin;

drop policy if exists weekly_hours_mgmt on public.weekly_hours;

create policy wh_perm_select on public.weekly_hours for select to authenticated
using ( public.perm_mode(auth.uid(),'shift') <> 'none' and not public.is_hr()
        and public.perm_proj_ok(auth.uid(),'shift', project_id, null) );
create policy wh_perm_insert on public.weekly_hours for insert to authenticated
with check ( public.perm_mode(auth.uid(),'shift') = 'edit' and not public.is_hr()
             and public.perm_proj_ok(auth.uid(),'shift', project_id, null) );
create policy wh_perm_update on public.weekly_hours for update to authenticated
using ( public.perm_mode(auth.uid(),'shift') = 'edit' and not public.is_hr()
        and public.perm_proj_ok(auth.uid(),'shift', project_id, null) )
with check ( public.perm_mode(auth.uid(),'shift') = 'edit' and not public.is_hr()
             and public.perm_proj_ok(auth.uid(),'shift', project_id, null) );
create policy wh_perm_delete on public.weekly_hours for delete to authenticated
using ( public.perm_mode(auth.uid(),'shift') = 'edit' and not public.is_hr()
        and public.perm_proj_ok(auth.uid(),'shift', project_id, null) );

commit;

-- ── ROLLBACK (manuell) ──
-- drop policy if exists wh_perm_select on public.weekly_hours; drop policy if exists wh_perm_insert on public.weekly_hours;
-- drop policy if exists wh_perm_update on public.weekly_hours; drop policy if exists wh_perm_delete on public.weekly_hours;
-- create policy weekly_hours_mgmt on public.weekly_hours for all to authenticated
--   using (is_management() or (is_planner() and (project_id = get_my_employee_project_id())))
--   with check (is_management() or (is_planner() and (project_id = get_my_employee_project_id())));
