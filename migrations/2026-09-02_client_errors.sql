-- =============================================================================
-- Fehlerfänger: client_errors  (Bruno Schnitt 1, aber eigenständig wertvoll)    2026-09-02
-- =============================================================================
-- Bisher sehen wir Frontend-Fehler nur, wenn jemand sie meldet. Ab jetzt sammelt der Browser JEDEN unbehandelten
-- Fehler automatisch (window.onerror + unhandledrejection), auch ohne dass jemand Bruno fragt. So entsteht eine
-- Übersicht, was im Alltag tatsächlich schiefgeht.
--
-- Rollup statt Flut: eine Zeile je Fehler-SIGNATUR (Art + Bereich + normalisierte Meldung + Quelle:Zeile), mit
-- Zähler und zuletzt-gesehen. Zahlen/Hashes in der Meldung werden für die Signatur zu # normalisiert, damit
-- „Fehler bei 464" und „Fehler bei 912" als EIN Fehler gezählt werden.
--
-- Geschrieben wird NUR über die security-definer-RPC log_client_error (jeder angemeldete Nutzer, auch MA, ohne
-- direktes Insert-Recht). Gelesen/verwaltet: nur Management.
-- =============================================================================

create table if not exists public.client_errors (
  sig            text primary key,
  kind           text,            -- 'error' | 'unhandledrejection'
  message        text,
  source         text,            -- Datei/URL des Fehlers
  lineno         int,
  colno          int,
  area           text,            -- Ansicht/Bereich, in dem es passierte (view-key)
  stack          text,
  sample_url     text,
  user_agent     text,
  count          int  not null default 1,
  first_seen     timestamptz not null default now(),
  last_seen      timestamptz not null default now(),
  last_user_id   uuid,
  last_user_name text,
  resolved_at    timestamptz
);
create index if not exists idx_client_errors_open on public.client_errors(resolved_at, last_seen desc);

alter table public.client_errors enable row level security;
drop policy if exists client_errors_mgmt_select on public.client_errors;
create policy client_errors_mgmt_select on public.client_errors for select to authenticated using (public.is_management());
drop policy if exists client_errors_mgmt_update on public.client_errors;
create policy client_errors_mgmt_update on public.client_errors for update to authenticated using (public.is_management()) with check (public.is_management());
drop policy if exists client_errors_mgmt_delete on public.client_errors;
create policy client_errors_mgmt_delete on public.client_errors for delete to authenticated using (public.is_management());
-- KEIN Insert-Policy: geschrieben wird ausschließlich über die RPC (definer).
grant select, update, delete on public.client_errors to authenticated;

-- -----------------------------------------------------------------------------
-- Log-RPC: nimmt die Fehlerfelder, bildet die Signatur, zählt hoch oder legt neu an.
-- security definer → jeder angemeldete Nutzer darf loggen, ohne Tabellenrecht.
-- -----------------------------------------------------------------------------
create or replace function public.log_client_error(p jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_norm text; v_sig text;
begin
  if auth.uid() is null then return; end if;   -- nur angemeldet
  v_norm := regexp_replace(coalesce(p->>'message',''), '[0-9a-fA-F]{8,}|[0-9]+', '#', 'g');
  v_sig  := md5(coalesce(p->>'kind','')||'|'||coalesce(p->>'area','')||'|'||v_norm||'|'||coalesce(p->>'source','')||':'||coalesce(p->>'lineno',''));
  insert into public.client_errors(sig,kind,message,source,lineno,colno,area,stack,sample_url,user_agent,last_user_id,last_user_name)
  values (v_sig, p->>'kind', left(p->>'message',500), left(p->>'source',300),
          nullif(p->>'lineno','')::int, nullif(p->>'colno','')::int, p->>'area', left(p->>'stack',2000),
          left(p->>'url',500), left(p->>'user_agent',300), auth.uid(), p->>'user_name')
  on conflict (sig) do update set
    count=public.client_errors.count+1, last_seen=now(),
    last_user_id=auth.uid(), last_user_name=excluded.last_user_name,
    message=excluded.message, area=excluded.area, sample_url=excluded.sample_url,
    user_agent=excluded.user_agent, stack=coalesce(excluded.stack, public.client_errors.stack),
    resolved_at=null;   -- taucht wieder auf → wieder offen
end $$;
grant execute on function public.log_client_error(jsonb) to authenticated;
