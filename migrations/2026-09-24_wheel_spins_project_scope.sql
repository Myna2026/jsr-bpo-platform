-- Glücksrad-Auszahlungen: Leads sehen nur ihr eigenes Team.
--
-- Befund beim Anlegen des Leitstand-Zugangs für Arsyela Delishaj (Projektleiterin Condor, 2026-09-24):
-- Die Policy "wheel_spins read internal" gab teamlead/projektleiter die Auszahlungen ALLER Projekte frei
-- (16 Zeilen aus Fabletics, HolidayCheck und Giganetz, keine davon aus ihrem Team). Das widerspricht
-- „nur das eigene Team". Der Punkt stand seit dem Audit vom 2026-09-04 offen.
--
-- Neu: Management/Finance/HR unverändert alles, Leads nur Mitarbeiter ihres Projekts, jeder seine eigene
-- Zeile (Policy "wheel_spins self read" bleibt unangetastet, sie trägt das Mitarbeiter-Portal).
-- is_emp_in_my_project() ist SECURITY DEFINER — ein direktes EXISTS auf employees liefe in die
-- employees-RLS und der Lead sähe gar nichts mehr.
--
-- Rückbau (falls die alte Reichweite gewollt ist):
--   drop policy "wheel_spins read internal" on public.wheel_spins;
--   create policy "wheel_spins read internal" on public.wheel_spins for select
--     using (exists (select 1 from app_users where user_id = auth.uid()
--                    and role_keys && array['management','hr','finance','teamlead','projektleiter']));

drop policy if exists "wheel_spins read internal" on public.wheel_spins;

create policy "wheel_spins read internal" on public.wheel_spins
  for select
  using (
    public.is_management() or public.is_finance() or public.is_hr()
    or (public.is_planner() and public.is_emp_in_my_project(emp_id))
  );
