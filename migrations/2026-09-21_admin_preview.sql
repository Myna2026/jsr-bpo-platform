-- Admin-Vorschau („Ansehen als“): der Admin bleibt angemeldet, schickt je Anfrage die Kopfzeile x-preview: <sitzung>.
-- PostgREST ruft vor jeder Anfrage preview_pre_request() auf; bei gültiger Sitzung wird die Anfrage READ-ONLY geschaltet und
-- die Nutzer-ID (auth.uid()) auf den Zielnutzer gesetzt, so gelten dessen RLS-Rechte, nicht die des Admins. Ohne Kopfzeile
-- passiert nichts. Notschalter: app_config 'jsr_preview_v1' -> {"off": true} legt die Umschaltung still.
-- Vom User am 2026-09-21 freigegeben (nur admin@tive360.de, 2 Stunden, Leseliste Conny + Coach-Probelauf).
create table if not exists public.preview_admins (user_id uuid primary key, added_at timestamptz not null default now(), note text);
create table if not exists public.preview_sessions (
  id uuid primary key default gen_random_uuid(),
  admin_uid uuid not null,
  target_uid uuid not null,
  target_email text,
  target_name text,
  portal text not null default 'hr',
  started_at timestamptz not null default now(),
  ended_at timestamptz
);
create index if not exists preview_sessions_admin_idx on public.preview_sessions(admin_uid, started_at desc);
alter table public.preview_admins enable row level security;
alter table public.preview_sessions enable row level security;
drop policy if exists preview_admins_self on public.preview_admins;
create policy preview_admins_self on public.preview_admins for select to authenticated using (user_id = auth.uid());
drop policy if exists preview_sessions_admin on public.preview_sessions;
create policy preview_sessions_admin on public.preview_sessions for select to authenticated using (admin_uid = auth.uid());

insert into public.preview_admins(user_id, note) values ('939dfd7c-f4ba-4a9e-aa2f-b3048544bffc', 'admin@tive360.de (User 2026-09-21: nur dieser Zugang)') on conflict do nothing;
insert into public.app_config(key, value) values ('jsr_preview_v1', '{"off": false, "hours": 2}'::jsonb) on conflict (key) do nothing;

-- Prüfung in eigener Funktion mit Fehlerfang (Subtransaktion). WICHTIG: das Read-only-Flag darf NICHT innerhalb eines
-- BEGIN/EXCEPTION-Blocks gesetzt werden, Postgres setzt transaction_read_only beim Verlassen der Subtransaktion zurück.
create or replace function public.preview_resolve() returns public.preview_sessions
language plpgsql security definer set search_path = public as $$
declare v_hdr text; v_claims jsonb; v_sub uuid; v_sess public.preview_sessions%rowtype; v_cfg jsonb; v_hours int; v_none public.preview_sessions%rowtype;
begin
  begin
    v_hdr := nullif(coalesce(current_setting('request.headers', true), '')::jsonb ->> 'x-preview', '');
    if v_hdr is null then return v_none; end if;
    select value into v_cfg from public.app_config where key = 'jsr_preview_v1';
    if coalesce((v_cfg->>'off')::boolean, false) then return v_none; end if;
    v_hours := greatest(1, least(12, coalesce((v_cfg->>'hours')::int, 2)));
    v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
    v_sub := nullif(v_claims->>'sub', '')::uuid;
    if v_sub is null then return v_none; end if;
    if not exists (select 1 from public.preview_admins where user_id = v_sub) then return v_none; end if;
    select * into v_sess from public.preview_sessions
      where id = v_hdr::uuid and admin_uid = v_sub and ended_at is null and started_at > now() - make_interval(hours => v_hours);
    return v_sess;
  exception when others then
    return v_none;
  end;
end $$;
-- Läuft vor JEDER Anfrage: ohne Kopfzeile sofort zurück; setzt bei gültiger Sitzung read-only und wechselt die Identität.
create or replace function public.preview_pre_request() returns void
language plpgsql security definer set search_path = public as $$
declare v_sess public.preview_sessions%rowtype; v_claims jsonb;
begin
  if coalesce(current_setting('request.headers', true), '') not like '%x-preview%' then return; end if;
  v_sess := public.preview_resolve();
  if v_sess.id is null then return; end if;
  -- Erst read-only, dann Identität wechseln: greift read-only nicht, wird nicht umgeschaltet
  perform set_config('transaction_read_only', 'on', true);
  if current_setting('transaction_read_only', true) <> 'on' then return; end if;
  v_claims := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb)
    || jsonb_build_object('sub', v_sess.target_uid::text, 'email', coalesce(v_sess.target_email, ''), 'preview_admin', v_sess.admin_uid::text, 'preview_session', v_sess.id::text);
  perform set_config('request.jwt.claims', v_claims::text, true);
  perform set_config('request.jwt.claim.sub', v_sess.target_uid::text, true);
  perform set_config('request.jwt.claim.email', coalesce(v_sess.target_email, ''), true);
end $$;
revoke all on function public.preview_resolve() from public;
revoke all on function public.preview_pre_request() from public;
grant execute on function public.preview_pre_request() to authenticator, authenticated, anon, service_role;

-- Sitzung starten (nur Admin)
create or replace function public.preview_start(p_target uuid, p_portal text default 'hr') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_id uuid; v_email text; v_name text;
begin
  if v_uid is null or not exists (select 1 from preview_admins where user_id = v_uid) then raise exception 'Keine Berechtigung für die Vorschau.'; end if;
  if p_target = v_uid then raise exception 'Die eigene Sicht braucht keine Vorschau.'; end if;
  select u.email, coalesce(a.full_name, u.email) into v_email, v_name from auth.users u left join app_users a on a.user_id = u.id where u.id = p_target;
  if v_email is null then raise exception 'Nutzer nicht gefunden.'; end if;
  update preview_sessions set ended_at = now() where admin_uid = v_uid and ended_at is null;   -- eine Vorschau je Admin
  insert into preview_sessions(admin_uid, target_uid, target_email, target_name, portal) values (v_uid, p_target, v_email, v_name, coalesce(p_portal, 'hr')) returning id into v_id;
  return jsonb_build_object('id', v_id, 'target_email', v_email, 'target_name', v_name, 'portal', coalesce(p_portal, 'hr'));
end $$;
create or replace function public.preview_end(p_id uuid) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  update preview_sessions set ended_at = now() where id = p_id and admin_uid = auth.uid() and ended_at is null; return found;
end $$;
-- Wer bin ich in dieser Anfrage? (unter Vorschau: der Zielnutzer, plus Kennzeichen)
create or replace function public.preview_whoami() returns jsonb
language sql security definer set search_path = public stable as $$
  select jsonb_build_object('user_id', auth.uid(), 'email', (current_setting('request.jwt.claims', true)::jsonb ->> 'email'),
    'preview_admin', (current_setting('request.jwt.claims', true)::jsonb ->> 'preview_admin'),
    'preview_session', (current_setting('request.jwt.claims', true)::jsonb ->> 'preview_session'),
    'app_user', (select to_jsonb(a) from app_users a where a.user_id = auth.uid()));
$$;
-- Nutzerliste fürs Dropdown (nur Admin): E-Mail steht in auth.users, daher Definer
create or replace function public.preview_list_users() returns jsonb
language sql security definer set search_path = public stable as $$
  select case when exists (select 1 from preview_admins where user_id = auth.uid())
    then coalesce((select jsonb_agg(jsonb_build_object('user_id', u.id, 'email', u.email, 'name', a.full_name, 'role_keys', a.role_keys, 'client_id', a.client_id, 'employee_id', a.employee_id, 'active', a.active, 'last_sign_in_at', u.last_sign_in_at) order by a.full_name)
      from auth.users u join app_users a on a.user_id = u.id where u.id <> auth.uid()), '[]'::jsonb)
    else '[]'::jsonb end;
$$;
revoke all on function public.preview_start(uuid, text), public.preview_end(uuid), public.preview_whoami(), public.preview_list_users() from public, anon;
grant execute on function public.preview_start(uuid, text), public.preview_end(uuid), public.preview_whoami(), public.preview_list_users() to authenticated;

-- PostgREST: Prüffunktion vor jeder Anfrage aktivieren (Notschalter: app_config jsr_preview_v1 {"off": true})
alter role authenticator set pgrst.db_pre_request = 'public.preview_pre_request';
notify pgrst, 'reload config';
