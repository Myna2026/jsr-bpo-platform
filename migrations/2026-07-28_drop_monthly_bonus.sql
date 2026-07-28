-- 2026-07-28  monthly_bonus entfernen (Feld ohne Wirkung)
--
-- Befund: monthly_bonus wurde nur geschrieben/importiert/persistiert/geloggt, aber NIRGENDS
-- für Kosten oder Lohn gelesen (calcFullPayslip nutzt rec.target_bonus/special_bonus/…, nicht
-- monthly_bonus; empMonthlyCost kennt es nicht). Gleiches Muster wie efficiency_pct/weekly_hours.
-- Das Gehaltsmodell führt Boni pro Monat manuell (special_bonus/target_bonus in salaryData) —
-- ein zweiter, stehender Bonuskanal widerspricht dem.
--
-- monthly_bonus ist eine ECHTE Spalte (aus 25b, supabase/employees_payroll_cols.sql) → DROP.
-- Zusätzlich Altresiduen aus extra räumen, damit das Feld nicht über den extra-Sink zurückkommt.
--
-- REIHENFOLGE: erst Frontend-Deploy (schreibt monthly_bonus nicht mehr, nicht in EMP_COLS),
-- DANN diese Migration im Supabase-SQL-Editor. Idempotent.

alter table public.employees drop column if exists monthly_bonus;
update public.employees set extra = extra - 'monthly_bonus' where extra ? 'monthly_bonus';
