-- =============================================================================
-- Fundament fuer die Auto-Parken-Regel (Clara): ein EHRLICHER "zuletzt von einem
-- Menschen bearbeitet"-Zeitstempel. updated_at taugt nicht (wird auch von Importen,
-- Clara-Automatik und Massen-Migrationen angefasst -> am 21.-24.8. wurden alle Zeilen
-- gebumpt, dadurch war der Leerlauf-Zeitpunkt verfaelscht).
--
-- last_worked_at wird NUR im menschlichen Schreibpfad gesetzt (Frontend saveCvToDB:
-- Bearbeiten, Statuswechsel, Testabschluss). Importe (bulkInsertCvs, Windsor/Meta),
-- markCvConvertedInDB und die Clara-Automatik fassen es NICHT an.
--
-- Stichtag-Semantik: Backfill = now(). Damit startet die 10-Tage-Uhr fuer ALLE heute
-- neu -> der bestehende Eingangs-Berg wird beim Einschalten NICHT sofort geparkt
-- (er bekommt eine frische Frist; separat von Hand zu triagieren). Neue Import-Leads
-- ohne last_worked_at zaehlen ab created_at (siehe coalesce im Clara-Scan).
-- Idempotent.
-- =============================================================================

alter table public.cvs add column if not exists last_worked_at timestamptz;

-- Stichtag: bestehende Zeilen bekommen die Uhr JETZT gestellt (verfaelschtes updated_at wird verworfen).
update public.cvs set last_worked_at = now() where last_worked_at is null;

-- Der Clara-Scan filtert nach (status, coalesce(last_worked_at, created_at)); passender Index.
create index if not exists idx_cvs_status_last_worked
  on public.cvs (status, last_worked_at);

notify pgrst, 'reload schema';
