-- Bewerber-Datenerhebung am Empfangs-Tablet, Schnitt 1: Fundament.
-- Absicherung der Bewerbernummer in drei Schichten:
--   1) public_code: 6-stelliger ZUFALLScode je Bewerber (kein Hochzählen -> kein Nachbar-Leck), einmalig,
--      ändert sich nie. Vergabe per Trigger beim Anlegen + Backfill der Bestandsbewerber.
--   2) Stations-Token: der dauerhafte Tablet-Link trägt ein langes Geheim-Token (jsr_vorort_station_v1).
--      Ohne gültiges, aktives Token liefert keine RPC Daten -> der Endpunkt ist öffentlich nicht erreichbar.
--   3) Brute-Force-Sperre: nur FEHLversuche werden gezählt (vorort_attempts, nur Zeitstempel, kein Code/Name);
--      zu viele Fehlgriffe in kurzer Zeit sperren die Suche zeitweise. Treffer zählen nicht mit.
-- Zugriff nur über SECURITY-DEFINER-RPCs (vorort_lookup/vorort_submit), die die cvs-RLS umgehen; anon darf
-- die RPCs aufrufen, aber cvs nie direkt lesen/schreiben.

-- ── 1) public_code ──────────────────────────────────────────────────────────
alter table public.cvs add column if not exists public_code text;
create unique index if not exists idx_cvs_public_code on public.cvs(public_code) where public_code is not null;

create or replace function public.gen_public_code() returns text language plpgsql as $$
declare c text;
begin
  loop
    c := lpad((floor(random()*900000)+100000)::int::text, 6, '0');
    exit when not exists (select 1 from public.cvs where public_code = c);
  end loop;
  return c;
end $$;

create or replace function public.cvs_assign_public_code() returns trigger language plpgsql as $$
begin
  if new.public_code is null then new.public_code := public.gen_public_code(); end if;
  return new;
end $$;
drop trigger if exists trg_cvs_public_code on public.cvs;
create trigger trg_cvs_public_code before insert on public.cvs for each row execute function public.cvs_assign_public_code();

-- Backfill Bestand: zeilenweise, damit die Eindeutigkeitsprüfung schon vergebene Codes derselben Transaktion sieht.
do $$ declare r record;
begin
  for r in select id from public.cvs where public_code is null loop
    update public.cvs set public_code = public.gen_public_code() where id = r.id;
  end loop;
end $$;

-- ── 2) Stations-Token ───────────────────────────────────────────────────────
insert into public.app_config(key, value)
values ('jsr_vorort_station_v1', jsonb_build_object('token', encode(gen_random_bytes(24),'hex'), 'active', true))
on conflict (key) do nothing;

create or replace function public.vorort_station_ok(p_station text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.app_config
    where key='jsr_vorort_station_v1'
      and coalesce((value->>'active')::boolean, false)
      and value->>'token' = p_station
      and coalesce(p_station,'') <> ''
  );
$$;

-- ── 3) Brute-Force-Sperre ───────────────────────────────────────────────────
create table if not exists public.vorort_attempts (id bigserial primary key, at timestamptz not null default now());
create index if not exists idx_vorort_attempts_at on public.vorort_attempts(at);
alter table public.vorort_attempts enable row level security;   -- keine Policy: nur Definer-RPCs kommen ran

-- ── Lookup: Profil zum Vorbefüllen laden ────────────────────────────────────
create or replace function public.vorort_lookup(p_station text, p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v public.cvs; n int;
begin
  if not public.vorort_station_ok(p_station) then return jsonb_build_object('ok', false, 'code', 'station'); end if;
  select count(*) into n from public.vorort_attempts where at > now() - interval '5 minutes';
  if n >= 12 then return jsonb_build_object('ok', false, 'code', 'locked'); end if;
  if coalesce(p_code,'') !~ '^\d{6}$' then
    insert into public.vorort_attempts default values;
    return jsonb_build_object('ok', false, 'code', 'notfound');
  end if;
  select * into v from public.cvs where public_code = p_code limit 1;
  if not found then
    insert into public.vorort_attempts default values;
    return jsonb_build_object('ok', false, 'code', 'notfound');
  end if;
  return jsonb_build_object('ok', true, 'cv', jsonb_build_object(
    'public_code', v.public_code, 'first_name', v.first_name, 'last_name', v.last_name,
    'email', v.email, 'phone', v.phone, 'city', v.city, 'birthday', v.birthday,
    'education', v.education, 'education_level', v.education_level, 'experience_years', v.experience_years,
    'work_history', v.work_history, 'language_level', v.language_level, 'writing_level', v.writing_level,
    'languages_str', v.languages_str, 'available_from', v.available_from, 'homeoffice_pref', v.homeoffice_pref,
    'extra', coalesce(v.extra, '{}'::jsonb)));
end $$;

-- ── Submit: alles auf einmal in die bestehende cvs-Zeile schreiben ───────────
-- Nur Schlüssel, die p_data tatsächlich enthält, werden geschrieben (sonst Bestand behalten). Leerer String
-- -> null. extra wird gemergt (work_hours/weekend/sunday/writing_sample etc.) + Marker vorort_at.
create or replace function public.vorort_submit(p_station text, p_code text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v public.cvs;
begin
  if not public.vorort_station_ok(p_station) then return jsonb_build_object('ok', false, 'code', 'station'); end if;
  select * into v from public.cvs where public_code = p_code limit 1;
  if not found then return jsonb_build_object('ok', false, 'code', 'notfound'); end if;
  update public.cvs set
    first_name       = case when p_data ? 'first_name'       then nullif(p_data->>'first_name','')            else first_name end,
    last_name        = case when p_data ? 'last_name'        then nullif(p_data->>'last_name','')             else last_name end,
    email            = case when p_data ? 'email'            then nullif(p_data->>'email','')                 else email end,
    phone            = case when p_data ? 'phone'            then nullif(p_data->>'phone','')                 else phone end,
    city             = case when p_data ? 'city'             then nullif(p_data->>'city','')                  else city end,
    birthday         = case when p_data ? 'birthday'         then nullif(p_data->>'birthday','')::date        else birthday end,
    education        = case when p_data ? 'education'        then nullif(p_data->>'education','')             else education end,
    education_level  = case when p_data ? 'education_level'  then nullif(p_data->>'education_level','')       else education_level end,
    experience_years = case when p_data ? 'experience_years' then nullif(p_data->>'experience_years','')::int else experience_years end,
    work_history     = case when p_data ? 'work_history'     then nullif(p_data->>'work_history','')          else work_history end,
    language_level   = case when p_data ? 'language_level'   then nullif(p_data->>'language_level','')        else language_level end,
    writing_level    = case when p_data ? 'writing_level'    then nullif(p_data->>'writing_level','')         else writing_level end,
    languages_str    = case when p_data ? 'languages_str'    then nullif(p_data->>'languages_str','')         else languages_str end,
    available_from   = case when p_data ? 'available_from'   then nullif(p_data->>'available_from','')::date  else available_from end,
    homeoffice_pref  = case when p_data ? 'homeoffice_pref'  then nullif(p_data->>'homeoffice_pref','')       else homeoffice_pref end,
    extra            = coalesce(extra,'{}'::jsonb) || coalesce(p_data->'extra','{}'::jsonb) || jsonb_build_object('vorort_at', now()),
    updated_at       = now()
  where public_code = p_code;
  return jsonb_build_object('ok', true, 'public_code', p_code);
end $$;

revoke all on function public.vorort_lookup(text,text)     from public;
revoke all on function public.vorort_submit(text,text,jsonb) from public;
grant execute on function public.vorort_lookup(text,text)     to anon, authenticated;
grant execute on function public.vorort_submit(text,text,jsonb) to anon, authenticated;
