-- =============================================================================
-- Aktivitaets-Protokoll (Login + Datenaenderungen)                    2026-07-21
-- =============================================================================
-- Zweck: nachvollziehen, wer sich wann eingeloggt und wer welche Daten geaendert
-- hat (5 Nutzer, echte Personaldaten). Das Protokoll ist UNVERAENDERLICH.
--
-- RLS:
--   Lesen  : nur management/hr/finance.
--   Schreiben: jeder eingeloggte Nutzer — aber nur mit der EIGENEN auth.uid()
--             (kein Faelschen fremder Handlungen). "Jeder protokolliert sein
--             eigenes Handeln" bleibt erfuellt.
--   Kein update/delete: keine Policy + kein Grant → Eintraege sind unveraenderlich.
--
-- user_name/entity_label werden als KLARTEXT mitgeschrieben, damit der Eintrag
-- auch nach Nutzer-/Datensatz-Loeschung lesbar bleibt.
--
-- Idempotent. Anzuwenden im Supabase SQL Editor (hier NICHT ausgefuehrt).
-- Voraussetzung: schema_auth.sql (app_users).
-- =============================================================================

create table if not exists public.activity_log (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid,                          -- wer (auth.users.id; kein FK, damit Log Nutzerloeschung ueberlebt)
  user_name    text,                          -- Klartext-Name (bleibt nach Loeschung lesbar)
  action       text not null,                 -- 'login' | 'create' | 'update' | 'delete'
  entity       text,                          -- 'employee' | 'project' | 'payroll_input' | 'shift_assignment' | 'session' | …
  entity_id    text,                          -- welcher Datensatz
  entity_label text,                          -- Klartext (z.B. Mitarbeitername) — ohne Nachschlagen verstaendlich
  details      jsonb,                         -- optional: z.B. gesetzte Lohn-Werte
  created_at   timestamptz not null default now()
);

create index if not exists idx_activity_created on public.activity_log (created_at desc);
create index if not exists idx_activity_user    on public.activity_log (user_id);
create index if not exists idx_activity_action  on public.activity_log (action);

alter table public.activity_log enable row level security;

-- Lesen: nur management/hr/finance (aktiver app_user).
drop policy if exists activity_read on public.activity_log;
create policy activity_read on public.activity_log
  for select to authenticated
  using (exists (select 1 from public.app_users u
                 where u.user_id = auth.uid() and u.active
                   and u.role_keys && array['management','hr','finance']::text[]));

-- Schreiben: jeder eingeloggte Nutzer, aber nur die EIGENE uid.
drop policy if exists activity_insert on public.activity_log;
create policy activity_insert on public.activity_log
  for insert to authenticated
  with check (user_id = auth.uid());

-- KEIN update/delete → unveraenderlich. Bewusst kein Grant dafuer.
grant select, insert on public.activity_log to authenticated;
