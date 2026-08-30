-- Taxonomie-Zuschnitt, Punkt 2: Bereich „Lohn & Wirtschaftlichkeit" teilen. Verschiedene Empfänger (User 2026-08-30):
--   • 'lohn' wird zu LOHNPFLEGE (payroll): hr IN (Deonita pflegt Löhne/Boni/Abzüge).
--   • 'wirtschaft' neu = WIRTSCHAFTLICHKEIT/Marge (profitability/productivity + forecast_actuals): mgmt/finance, hr RAUS.
-- WICHTIG: Der Schutz für Management-Mitarbeiter (is_protected_employee: Deonita pflegt Löhne, aber nicht die der
-- Geschäftsführung) bleibt in den Tabellen-Policies (payslips/payroll_inputs/vacation_accounts) erhalten — er hängt
-- NICHT am Bereichs-Seed und geht durch diesen Zuschnitt nicht verloren.

begin;

insert into public.permission_areas(key,label,seq,axes,menu_keys) values
  ('wirtschaft','Wirtschaftlichkeit',15,
   '{"gehalt":true,"projekt":true,"hierarchie":false,"skill":false}'::jsonb,
   array['profitability','productivity']);

update public.permission_areas set label='Lohnpflege', menu_keys=array['payroll'] where key='lohn';

-- Seeds wirtschaft: nur Management + Finance (Marge, hr raus).
insert into public.role_permissions(role_key,area_key,visible,mode,salary,direction,projects,project_ids,skill) values
  ('management','wirtschaft',true,'edit','all','side','all','{}'::text[],'all'),
  ('finance','wirtschaft',true,'edit','all','side','all','{}'::text[],'all'),
  ('hr','wirtschaft',false,'none','none','side','all','{}'::text[],'all'),
  ('projektleiter','wirtschaft',false,'none','none','side','own','{}'::text[],'all'),
  ('teamlead','wirtschaft',false,'none','none','side','own','{}'::text[],'all');

-- lohn (Lohnpflege): hr rein (sichtbar, bearbeiten, Gehalt). Schutz der GF-Löhne bleibt in den Tabellen-Policies.
update public.role_permissions set visible=true, mode='edit', salary='all'
  where area_key='lohn' and role_key='hr';

-- forecast_actuals von 'lohn' auf 'wirtschaft' umhängen (es ist Marge, nicht Lohnpflege). Ohne das bekäme hr
-- durch die Lohnpflege-Öffnung Zugriff auf Umsatz/Kosten. Effekt unverändert (mgmt/finance), nur der Bereich wechselt.
drop policy if exists fa_perm_select on public.forecast_actuals;
drop policy if exists fa_perm_insert on public.forecast_actuals;
drop policy if exists fa_perm_update on public.forecast_actuals;
drop policy if exists fa_perm_delete on public.forecast_actuals;

create policy fa_perm_select on public.forecast_actuals for select to authenticated
using ( public.perm_mode(auth.uid(),'wirtschaft') <> 'none'
        and public.perm_proj_ok(auth.uid(),'wirtschaft', project_id, null) );
create policy fa_perm_insert on public.forecast_actuals for insert to authenticated
with check ( public.perm_mode(auth.uid(),'wirtschaft') = 'edit'
             and public.perm_proj_ok(auth.uid(),'wirtschaft', project_id, null) );
create policy fa_perm_update on public.forecast_actuals for update to authenticated
using ( public.perm_mode(auth.uid(),'wirtschaft') = 'edit'
        and public.perm_proj_ok(auth.uid(),'wirtschaft', project_id, null) )
with check ( public.perm_mode(auth.uid(),'wirtschaft') = 'edit'
             and public.perm_proj_ok(auth.uid(),'wirtschaft', project_id, null) );
create policy fa_perm_delete on public.forecast_actuals for delete to authenticated
using ( public.perm_mode(auth.uid(),'wirtschaft') = 'edit'
        and public.perm_proj_ok(auth.uid(),'wirtschaft', project_id, null) );

commit;

-- ── ROLLBACK (manuell) ──
-- update public.role_permissions set visible=false, mode='none', salary='none' where area_key='lohn' and role_key='hr';
-- delete from public.role_permissions where area_key='wirtschaft';
-- update public.permission_areas set label='Lohn & Wirtschaftlichkeit', menu_keys=array['payroll','profitability','productivity'] where key='lohn';
-- delete from public.permission_areas where key='wirtschaft';
-- (forecast_actuals fa_perm_* zurück auf 'lohn' — siehe migrations/2026-08-30_rls_lohn_forecast_actuals.sql)
