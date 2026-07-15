-- ============================================================================
-- vacation_requests — Migration: 3 Typen + counter-Status + Gegenvorschlag
-- Idempotent. REIHENFOLGE: dieses SQL ZUERST ausführen + verifizieren,
-- ERST DANN das Frontend deployen. Sonst schlagen Insert/Update mit
-- 'special'/'counter' hart fehl (23514) und counter_proposal-Writes laufen
-- gegen eine nicht existierende Spalte.
-- ============================================================================

-- 1) type-CHECK: 'special' aufnehmen (Sonderurlaub, bezahlt, kein Saldo-Abzug)
alter table public.vacation_requests
  drop constraint if exists vacation_requests_type_check;
alter table public.vacation_requests
  add  constraint vacation_requests_type_check
  check (type in ('vacation','special','unpaid'));

-- 2) status-CHECK: 'counter' aufnehmen (HR-Gegenvorschlag, wartet auf MA)
alter table public.vacation_requests
  drop constraint if exists vacation_requests_status_check;
alter table public.vacation_requests
  add  constraint vacation_requests_status_check
  check (status in ('pending','approved','rejected','counter'));

-- 3) Gegenvorschlag {from,to} — nullable
alter table public.vacation_requests
  add column if not exists counter_proposal jsonb;


-- ---- Verifikation (Ausgabe posten) -----------------------------------------
-- Erwartet: type-CHECK mit vacation/special/unpaid, status-CHECK mit
-- pending/approved/rejected/counter, Spalte counter_proposal (jsonb) vorhanden.
select conname, pg_get_constraintdef(oid) as def
  from pg_constraint
 where conrelid = 'public.vacation_requests'::regclass and contype = 'c'
 order by conname;

select column_name, data_type
  from information_schema.columns
 where table_schema = 'public' and table_name = 'vacation_requests'
   and column_name = 'counter_proposal';
