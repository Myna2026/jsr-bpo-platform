-- =============================================================================
-- Urlaubskonto — Schnitt 1: Datenmodell (zwei Töpfe)                      2026-08-04
-- =============================================================================
-- Zwei Töpfe je Mitarbeiter und Jahr:
--   Topf A = Resturlaub Vorjahr  -> hier als `carry_in_days` (manuell je MA, importierbar)
--   Topf B = Anspruch lauf. Jahr -> NICHT gespeichert, kommt aus der geteilten Formel
--            (JSRCalc.vacationQuota, shared/jsr-calc.js). Das Konto rechnet Schnitt 2.
--
-- EIGENE Tabelle mit (employee_id, year) statt Feld am Mitarbeiter, damit 2026, 2027, …
-- getrennt geführt werden. `carry_expires_on` = Verfall-Override je MA (leer = systemweiter
-- Standard aus der Urlaubs-Config). Verbrauch (genommen + genehmigt geplant) bleibt in
-- employees.absences[] und wird in Schnitt 2 vom einen geteilten Motor gezählt — hier NICHT.
--
-- Systemweiter Verfall-Standard: als `carry_expire` (MM-DD) in app_config 'jsr_vacation_cfg'.
-- Dieselbe Config-Zeile, die das MA-Portal bereits über APP_CFG.vacation liest (RLS deckt
-- 'mitarbeiter'); der neue Schlüssel wird dort also automatisch mitgelesen.
--
-- Backfill: der bestehende Resturlaub-Wert liegt im employees.extra-jsonb unter
-- 'vacation_carryover_2025' (keine eigene Spalte). Er wird als Topf A für 2026 übernommen,
-- BEVOR das Altfeld abgelöst wird. 'vacation_taken_ytd' wird bewusst NICHT übernommen
-- (ist "genommen", kein Resturlaub → Schnitt 3 als datierte Einträge).
--
-- Abhängigkeit: is_admin() (management/hr) + get_my_employee_id() existieren. Idempotent.
-- Im Supabase SQL-Editor ausführen.
-- =============================================================================

-- ── Konto-Tabelle: ein Topf-A-Eintrag je Mitarbeiter und Jahr ────────────────
create table if not exists public.vacation_accounts (
  employee_id      uuid not null references public.employees(id) on delete cascade,
  year             int  not null,
  carry_in_days    numeric not null default 0,        -- Resturlaub Vorjahr (Topf A), halbe Tage erlaubt
  carry_expires_on date,                              -- Verfall-Override je MA; leer = systemweiter Standard
  note             text,
  updated_at       timestamptz not null default now(),
  primary key (employee_id, year),
  constraint vacation_accounts_year_chk check (year between 2020 and 2100)
);
create index if not exists idx_vacation_accounts_year on public.vacation_accounts (year);

-- ── RLS: HR/Management pflegen alles, Mitarbeiter liest NUR die eigene Zeile ──
alter table public.vacation_accounts enable row level security;

drop policy if exists va_select on public.vacation_accounts;
create policy va_select on public.vacation_accounts
  for select to authenticated
  using ( public.is_admin() or employee_id = public.get_my_employee_id() );

drop policy if exists va_insert on public.vacation_accounts;
create policy va_insert on public.vacation_accounts
  for insert to authenticated with check ( public.is_admin() );

drop policy if exists va_update on public.vacation_accounts;
create policy va_update on public.vacation_accounts
  for update to authenticated using ( public.is_admin() ) with check ( public.is_admin() );

drop policy if exists va_delete on public.vacation_accounts;
create policy va_delete on public.vacation_accounts
  for delete to authenticated using ( public.is_admin() );

grant select, insert, update, delete on public.vacation_accounts to authenticated;

-- ── Backfill Topf A: extra->>'vacation_carryover_2025' -> Jahr 2026 ──────────
-- Nur numerische, von 0 verschiedene Werte. Idempotent (vorhandene Zeile bleibt unangetastet).
insert into public.vacation_accounts (employee_id, year, carry_in_days, note)
select e.id, 2026, (e.extra->>'vacation_carryover_2025')::numeric,
       'Backfill aus vacation_carryover_2025 (2026-08-04)'
from public.employees e
where nullif(e.extra->>'vacation_carryover_2025','') is not null
  and (e.extra->>'vacation_carryover_2025') ~ '^-?[0-9]+(\.[0-9]+)?$'
  and (e.extra->>'vacation_carryover_2025')::numeric <> 0
on conflict (employee_id, year) do nothing;

-- ── Systemweiter Verfall-Standard in die Urlaubs-Config (MM-DD, hier 30.06.) ──
-- Vorhandenen Wert NICHT überschreiben; nur ergänzen, falls er fehlt. Andere Config-Keys bleiben.
insert into public.app_config (key, value, updated_at)
values ('jsr_vacation_cfg', jsonb_build_object('carry_expire','06-30'), now())
on conflict (key) do update
  set value = coalesce(app_config.value,'{}'::jsonb)
              || jsonb_build_object('carry_expire', coalesce(app_config.value->>'carry_expire','06-30')),
      updated_at = now();

-- ── Kontrolle (optional): übernommene Konten anzeigen ────────────────────────
-- select employee_id, year, carry_in_days, carry_expires_on from public.vacation_accounts order by year, employee_id;
