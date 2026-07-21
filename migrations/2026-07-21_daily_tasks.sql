-- =============================================================================
-- Tagesaufgaben: gemeinsame tägliche Datenpflege-Checkliste            2026-07-21
-- =============================================================================
-- Gemeinsame Liste (NICHT pro Nutzer): hakt einer eine Aufgabe ab, sehen alle
-- anderen sie als erledigt. Ein Eintrag pro Aufgabe pro Tag; done_by/name/at
-- halten fest, wer wann erledigt hat. Am nächsten Tag (neues date) alles offen.
-- Haken lässt sich wieder entfernen (delete) → für alle wieder offen.
--
-- Idempotent (create table/policy if not exists, drop policy if exists). Anzuwenden
-- im Supabase SQL Editor (hier NICHT ausgeführt). Voraussetzung: schema_auth.sql.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1 Tabelle — Primärschlüssel (task_key, date): genau eine Zeile pro Aufgabe/Tag
-- -----------------------------------------------------------------------------
create table if not exists public.daily_tasks_done (
  task_key     text not null,
  date         date not null,
  done_by      uuid references auth.users(id) on delete set null,
  done_by_name text,
  done_at      timestamptz not null default now(),
  primary key (task_key, date)
);

alter table public.daily_tasks_done enable row level security;


-- -----------------------------------------------------------------------------
-- §2 RLS — gemeinsam für interne Rollen: jeder aktive app_user OHNE Kunden-Rolle
--    sieht ALLE Haken und darf setzen/entfernen. (Kunden sind ausgeschlossen.)
--    Die Subquery liest nur die EIGENE app_users-Zeile (self-select-Policy) → ok.
-- -----------------------------------------------------------------------------
drop policy if exists dtd_internal on public.daily_tasks_done;
create policy dtd_internal on public.daily_tasks_done
  for all to authenticated
  using (      exists (select 1 from public.app_users u
                        where u.user_id = auth.uid() and u.active
                          and not ('kunde' = any(coalesce(u.role_keys, '{}'::text[])))) )
  with check ( exists (select 1 from public.app_users u
                        where u.user_id = auth.uid() and u.active
                          and not ('kunde' = any(coalesce(u.role_keys, '{}'::text[])))) );

grant select, insert, update, delete on public.daily_tasks_done to authenticated;


-- -----------------------------------------------------------------------------
-- §3 Realtime — damit ein Haken bei allen offenen Sessions live erscheint.
--    (Falls die Tabelle schon in der Publication liegt, wirft dieser Befehl einen
--     Fehler — dann einfach überspringen.)
-- -----------------------------------------------------------------------------
alter publication supabase_realtime add table public.daily_tasks_done;
