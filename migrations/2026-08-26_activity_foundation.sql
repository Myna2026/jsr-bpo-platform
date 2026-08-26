-- Nutzungs-Erfassung, Fundament (für die tägliche Zusammenfassung / Maya).
-- Ergänzt das bestehende activity_log (Schreibvorgänge + Login) um:
--   1) Sitzungen mit Heartbeat -> echte Anwesenheitsdauer, auch reine Lese-Sitzungen (wer eine Stunde liest
--      ohne zu schreiben, war anwesend und soll sichtbar sein).
--   2) Index für die späteren 30-Tage-Auswertungen je User.
-- View-Logging (Bereichswechsel) und das Mitloggen des Aufgaben-Abhakens laufen über das bestehende
-- activity_log (action='view' bzw. 'task_done') aus dem Frontend — kein neues Schema nötig.
-- Additiv/idempotent.

begin;

-- ── Sitzungen (Heartbeat) ─────────────────────────────────────────────────────
create table if not exists public.user_sessions (
  session_id  text primary key,                 -- clientseitig erzeugt (uuid) je Seiten-/Login-Sitzung
  user_id     uuid not null,
  user_name   text,
  started_at  timestamptz not null default now(),
  last_seen   timestamptz not null default now(),
  ping_count  int not null default 1,
  view_key    text,                              -- zuletzt gesehener Bereich (bequem für die Übersicht)
  user_agent  text
);
create index if not exists idx_user_sessions_user on public.user_sessions(user_id, started_at desc);
alter table public.user_sessions enable row level security;
-- Lesen nur Management (Maya ist Management-only). Geschrieben wird ausschließlich über session_ping (definer).
drop policy if exists user_sessions_sel on public.user_sessions;
create policy user_sessions_sel on public.user_sessions for select to authenticated using (public.is_management());
grant select on public.user_sessions to authenticated;

-- Heartbeat: legt die Sitzung beim ersten Ping an, danach nur last_seen/ping_count/view_key fortschreiben.
-- Dauer je Sitzung = last_seen - started_at. Läuft als SECURITY DEFINER (umgeht RLS, self-write sauber).
create or replace function public.session_ping(p_session_id text, p_view text default null, p_agent text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_name text;
begin
  if auth.uid() is null then return; end if;
  select coalesce(full_name,'') into v_name from public.app_users where user_id = auth.uid();
  insert into public.user_sessions(session_id, user_id, user_name, view_key, user_agent)
    values (p_session_id, auth.uid(), v_name, p_view, p_agent)
  on conflict (session_id) do update
    set last_seen  = now(),
        ping_count = public.user_sessions.ping_count + 1,
        view_key   = coalesce(excluded.view_key, public.user_sessions.view_key);
end $$;
revoke all    on function public.session_ping(text, text, text) from public;
grant execute on function public.session_ping(text, text, text) to authenticated;

-- ── Index für 30-Tage-Auswertungen (aktive Tage/Aktionen je User) ────────────
create index if not exists idx_activity_log_user_time on public.activity_log(user_id, created_at desc);

commit;
