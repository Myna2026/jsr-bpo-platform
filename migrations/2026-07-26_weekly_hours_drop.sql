-- weekly_hours vollständig entfernen — NACH dem Code-Deploy ausführen.
-- Kehrtwende zur Aufwertung: weekly_hours (und monthly_hours) waren import-only und im
-- HR-Portal nicht pflegbar, überschrieben aber still die editierbaren Tagesstunden
-- (work_hours). Einzige Wahrheit ist jetzt work_hours × 5 × 4.33.
--
-- REIHENFOLGE: erst Code deployen (EMP_COLS/Import schreiben weekly_hours nicht mehr,
-- calcEmpTarget/EmpHoursWidget lesen es nicht mehr), DANN das hier. Umgekehrt gäbe es
-- 400er beim Speichern (EMP_COLS zeigt auf eine gedroppte Spalte) — wie bei work_weekend.
--
-- Verlustfrei bestätigt: 0 MA haben weekly_hours ohne work_hours.
-- Entfernt Spalte UND den (aus Teil 1 verbliebenen) extra-Key.

alter table public.employees drop column if exists weekly_hours;

update public.employees
  set extra = extra - 'weekly_hours'
  where extra ? 'weekly_hours';
