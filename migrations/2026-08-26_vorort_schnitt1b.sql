-- Tablet-Vorhaben, Ergänzung zu Schnitt 1: die drei Felder des Papierbogens, die bisher fehlten.
--  1) ADRESSE strukturiert: street/postal_code/country als Spalten (city gab es schon) -> filter-/auswertbar.
--  2) BERUFSSTATIONEN einzeln: als Liste extra.work_stations = [{company, from, to, tasks}] (beliebig viele,
--     statt eines Freitextfelds). Fließt durch den bestehenden extra-Merge, kein Schema nötig.
--  3) UNTERSCHRIFT: extra.vorort_signature = {statement, signed_at, image}. NUR die Tablet-Fassung setzt das;
--     die Mail-Anreicherung schreibt sie nie. Fingerzeichnung als kleines PNG (Data-URL) direkt in extra
--     (dauerhaft sichtbar, kein Bucket/Signed-URL-Ablauf; Bild wird clientseitig klein gehalten).
-- Nur die Adress-Spalten brauchen eine Schemaänderung; work_stations + Unterschrift laufen über extra.

alter table public.cvs add column if not exists street       text;
alter table public.cvs add column if not exists postal_code  text;
alter table public.cvs add column if not exists country      text;

-- Lookup um die Adress-Spalten erweitern (work_stations + Unterschrift kommen bereits über 'extra' zurück).
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
    'email', v.email, 'phone', v.phone,
    'street', v.street, 'postal_code', v.postal_code, 'city', v.city, 'country', v.country,
    'birthday', v.birthday,
    'education', v.education, 'education_level', v.education_level, 'experience_years', v.experience_years,
    'work_history', v.work_history, 'language_level', v.language_level, 'writing_level', v.writing_level,
    'languages_str', v.languages_str, 'available_from', v.available_from, 'homeoffice_pref', v.homeoffice_pref,
    'extra', coalesce(v.extra, '{}'::jsonb)));
end $$;

-- Submit um die Adress-Spalten erweitern. work_stations + vorort_signature kommen über p_data->'extra' und
-- werden vom bestehenden extra-Merge übernommen.
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
    street           = case when p_data ? 'street'           then nullif(p_data->>'street','')                else street end,
    postal_code      = case when p_data ? 'postal_code'      then nullif(p_data->>'postal_code','')           else postal_code end,
    city             = case when p_data ? 'city'             then nullif(p_data->>'city','')                  else city end,
    country          = case when p_data ? 'country'          then nullif(p_data->>'country','')               else country end,
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
