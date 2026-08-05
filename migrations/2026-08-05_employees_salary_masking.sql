-- =============================================================================
-- HR-Sperre — Schnitt 2: employees Spalten-Maskierung (Gehalt/Vertrag)     2026-08-05
-- =============================================================================
-- Person bleibt für HR sichtbar (Stammdaten/Abwesenheit/Onboarding), NUR die
-- Gehalts-/Vertragskonditionen werden verborgen. Zwei serverseitige Bausteine:
--
-- 1) LESEN — maskierende View `employees_masked` (security definer):
--    Liefert ALLE Zeilen; für geschützte Personen (is_protected_employee) und einen
--    Betrachter, der NICHT management/finance ist (= HR), werden nur diese 6 Spalten
--    auf NULL gesetzt: fixed_salary, hourly_rate, salary_currency, bank, contract,
--    id_number. Alles andere (Adresse, Stadt, Telefon, E-Mail, Geburtstag, Absences,
--    Status, Skills …) bleibt sichtbar. jsonb-Ansatz → robust gegen neue Spalten.
--    Zusatzspalte `_masked` = ob diese Zeile für den Betrachter maskiert ist (Frontend
--    macht die Gehalts-/Vertragsfelder dann read-only).
--    Management/Finance sehen über dieselbe View die vollen Werte (CASE greift nicht).
--
-- 2) SCHREIBEN — Trigger `protect_salary_on_update`:
--    Gehalt und Abwesenheiten teilen sich die employees-Zeile. Speichert HR eine
--    Abwesenheit für einen geschützten MA, käme das maskierte NULL-Gehalt zurück.
--    Der Trigger setzt die 6 Spalten für HR (nicht management/finance) hart auf OLD
--    zurück → Gehalt/Vertrag bleiben unversehrt, HR kann trotzdem Absences/Onboarding
--    schreiben.
--
-- NICHT hier (Schnitt 2b, eigener koordinierter Schritt): der HR-Entzug des DIREKTEN
-- SELECT auf public.employees (Basis-Policy) — erst danach ist der Konsolen-/Realtime-
-- Pfad dicht. Braucht die exakten Policy-Namen (Diagnose) + Umstellung der wenigen
-- Direktabfragen. Bis dahin ist die Anzeige über die View maskiert.
--
-- Abhängig von is_protected_employee()/is_management()/is_finance() (Schnitt 1).
-- Idempotent. Im Supabase SQL-Editor ausführen.
-- =============================================================================

-- ── 1) Maskierende View ──────────────────────────────────────────────────────
drop view if exists public.employees_masked;
create view public.employees_masked
with (security_invoker = false, security_barrier = true) as
select
  (jsonb_populate_record(
     null::public.employees,
     case
       when public.is_protected_employee(e.id)
            and not (public.is_management() or public.is_finance())
       then to_jsonb(e)
            - 'fixed_salary' - 'hourly_rate' - 'salary_currency'
            - 'bank' - 'contract' - 'id_number'
       else to_jsonb(e)
     end
   )).*,
  (public.is_protected_employee(e.id)
   and not (public.is_management() or public.is_finance())) as _masked
from public.employees e
where public.is_management() or public.is_hr() or public.is_finance();

grant select on public.employees_masked to authenticated;

-- ── 2) Gehalts-/Vertrags-Schutz beim UPDATE (HR schreibt Absences, nicht Gehalt) ──
create or replace function public.protect_salary_on_update()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if public.is_protected_employee(NEW.id)
     and not (public.is_management() or public.is_finance()) then
    NEW.fixed_salary    := OLD.fixed_salary;
    NEW.hourly_rate     := OLD.hourly_rate;
    NEW.salary_currency := OLD.salary_currency;
    NEW.bank            := OLD.bank;
    NEW.contract        := OLD.contract;
    NEW.id_number       := OLD.id_number;
  end if;
  return NEW;
end $$;

drop trigger if exists trg_protect_salary_on_update on public.employees;
create trigger trg_protect_salary_on_update
  before update on public.employees
  for each row execute function public.protect_salary_on_update();

-- ── Prüfabfrage (optional) ───────────────────────────────────────────────────
-- Als HR eingeloggt sollte fixed_salary bei Edi/Shkurte NULL sein, _masked = true:
--   select id, first_name, last_name, fixed_salary, _masked from public.employees_masked order by _masked desc;
