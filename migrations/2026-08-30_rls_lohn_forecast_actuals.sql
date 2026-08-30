-- Rechte Schnitt 6, Scheibe 6 (Lohn & Wirtschaftlichkeit): NUR forecast_actuals (Umsatz/Kosten/Marge) aufs Modell.
-- Bereich 'lohn'. Entscheidung (User 2026-08-30): Marge braucht hr NICHT → Verengung auf mgmt/finance ist richtig
-- (gewollter Soll, deckt sich mit dem lohn-Seed hr=none). Parität: hr 4->0 (gewollt), mgmt=4, Leads/MA=0.
--
-- BEWUSST NICHT in diesem Schnitt (der Bereich „Lohn & Wirtschaftlichkeit" ist zu grob, verschiedene Empfänger):
--  • payroll_inputs (Boni/Abzüge/Zuschläge): MUSS hr-offen bleiben (Deonita pflegt die Lohneingaben) → bleibt auf
--    IST-Policy mgmt/hr/finance. Das Modell (lohn hr=none) würde hr aussperren = Arbeit unmöglich. Zurückgestellt.
--  • payslips + vacation_accounts: hr-außer-geschützt + self (is_protected_employee) = die hr-kein-Mgmt-Daten-Logik,
--    an die Mitarbeiter-Gehalt-/Schutz-Sensibilität gekoppelt, nicht an die Marge. Unangetastet.
--  • forecast_demand/forecast_config (Workforce-Bedarf/FTE-Config) + report_forecast (Berichtsfolie): gar nicht Lohn.
-- Alles auf der Taxonomie-Liste (Bereich teilen: Lohnpflege hr-in vs. Margenauswertung hr-out).

begin;

drop policy if exists "forecast_actuals HR write" on public.forecast_actuals;
drop policy if exists "forecast_actuals read internal" on public.forecast_actuals;

create policy fa_perm_select on public.forecast_actuals for select to authenticated
using ( public.perm_mode(auth.uid(),'lohn') <> 'none'
        and public.perm_proj_ok(auth.uid(),'lohn', project_id, null) );

create policy fa_perm_insert on public.forecast_actuals for insert to authenticated
with check ( public.perm_mode(auth.uid(),'lohn') = 'edit'
             and public.perm_proj_ok(auth.uid(),'lohn', project_id, null) );

create policy fa_perm_update on public.forecast_actuals for update to authenticated
using ( public.perm_mode(auth.uid(),'lohn') = 'edit'
        and public.perm_proj_ok(auth.uid(),'lohn', project_id, null) )
with check ( public.perm_mode(auth.uid(),'lohn') = 'edit'
             and public.perm_proj_ok(auth.uid(),'lohn', project_id, null) );

create policy fa_perm_delete on public.forecast_actuals for delete to authenticated
using ( public.perm_mode(auth.uid(),'lohn') = 'edit'
        and public.perm_proj_ok(auth.uid(),'lohn', project_id, null) );

commit;

-- ── ROLLBACK (manuell) ──
-- drop policy if exists fa_perm_select on public.forecast_actuals;
-- drop policy if exists fa_perm_insert on public.forecast_actuals;
-- drop policy if exists fa_perm_update on public.forecast_actuals;
-- drop policy if exists fa_perm_delete on public.forecast_actuals;
-- create policy "forecast_actuals HR write" on public.forecast_actuals for all to authenticated
--   using (exists (select 1 from app_users where user_id=auth.uid() and role_keys && array['management','hr','finance']::text[]))
--   with check (exists (select 1 from app_users where user_id=auth.uid() and role_keys && array['management','hr','finance']::text[]));
-- create policy "forecast_actuals read internal" on public.forecast_actuals for select to authenticated
--   using (exists (select 1 from app_users where user_id=auth.uid() and role_keys && array['management','hr','finance']::text[]));
