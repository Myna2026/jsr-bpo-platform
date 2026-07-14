-- ============================================================================
-- TIVE 360° — CV-/Bewerber-Pipeline + Showcases auf Supabase (Blocker 1)
-- Einfügen im Supabase SQL Editor. Idempotent (kann erneut ausgeführt werden).
--
-- Ersetzt localStorage jsr_cvs_v1 + jsr_showcases_v1 (per-Device, cross-subdomain
-- tot) durch geteilte Tabellen. START LEER — keine Datenmigration (402 GDoc-
-- Rohimporte + 4 Dummies verworfen). GDoc-Sync füllt cvs ab dann direkt.
--
-- Prädikate 1:1 aus den Bestands-Migrationen:
--   HR-Vollzugriff  = 25a_employees_supabase.sql ('management','hr','finance')
--   Kunde→Projekt   = 25e get_my_client_project_id() (wird wiederverwendet)
--   set_updated_at()= schema_auth.sql §5 (wird wiederverwendet)
-- ============================================================================

create extension if not exists pgcrypto;   -- gen_random_bytes für Token


-- ----------------------------------------------------------------------------
-- 1) cvs — Bewerber. Flach für Identität/Filter/Sort + Whitelist-Anzeige,
--    jsonb für Nested, extra jsonb für Overflow (unbekannte GDoc-Felder).
--    persons-kompatibel: stabile uuid + status nach dem 19-Phasen-Modell.
-- ----------------------------------------------------------------------------
create table if not exists public.cvs (
  id               uuid primary key default gen_random_uuid(),
  -- Identität / Filter / Sort
  first_name       text,
  last_name        text,
  email            text,
  phone            text,
  city             text,
  status           text not null default 'cv_inbound',
  project_id       text,               -- = target_project (text, wie employees)
  target_role      text,
  source           text,               -- HR | gdoc | ...
  cv_date          date,
  -- Profil / Anzeige (Teil der Showcase-Whitelist)
  age              integer,
  gender           text,
  dialect          text,
  education        text,
  education_level  text,
  experience_years integer,
  work_history     text,
  language_level   text,
  writing_level    text,
  languages_str    text,
  homeoffice_pref  text,
  available_from   date,
  dream            text,
  hobbies          text,
  favorite_food    text,               -- Whitelist-Feld (Showcase), analog EmployeeModal
  travel_wish      text,
  photo_url        text,
  photo_color      text,
  better_email     boolean,
  better_phone     boolean,
  -- Interne Einschätzung — NICHT in der öffentlichen Whitelist
  notes            text,
  is_structured    boolean,
  sales_potential  boolean,
  -- Nested (jsonb)
  test_answers     jsonb default '{}'::jsonb,
  test_scores      jsonb default '{}'::jsonb,
  audios           jsonb default '[]'::jsonb,
  videos           jsonb default '[]'::jsonb,
  ai_reasoning     jsonb default '{}'::jsonb,
  -- Overflow (test_token, test_completed, primary_skill, status_changed, ...)
  extra            jsonb default '{}'::jsonb,
  created_at       timestamptz default now(),
  updated_at       timestamptz default now(),
  -- Status: nur die 19 dokumentierten Phasen. Legacy (new/reviewed/test_done/
  -- selected/presented/rejected_by_applicant) sind bewusst NICHT erlaubt.
  constraint cvs_status_valid check (status in (
    'cv_inbound','cv_accepted','cv_confirmed','invited','interview','selection1','selection2',
    'contract','training_planned','training','active','inactive',
    'parking',
    'rejected_by_us','rejected_by_employee','rejected_by_client','blacklist',
    'terminated_by_us','terminated_by_employee'
  ))
);
create index if not exists idx_cvs_status     on public.cvs(status);
create index if not exists idx_cvs_project_id on public.cvs(project_id);
create index if not exists idx_cvs_email      on public.cvs(email);

-- Nachtrag (idempotent): favorite_food auch auf Bestandstabellen sicherstellen.
alter table public.cvs add column if not exists favorite_food text;


-- ----------------------------------------------------------------------------
-- 2) showcases — Kandidaten-Präsentationen. Token = Bearer-Capability.
--    Token-Default: kryptografisch zufällig, 48 Hex-Zeichen (>= 32).
-- ----------------------------------------------------------------------------
create table if not exists public.showcases (
  id          uuid primary key default gen_random_uuid(),
  project_id  text not null,
  title       text,
  note        text,
  cv_ids      uuid[] not null default '{}',
  token       text not null unique default encode(gen_random_bytes(24),'hex'),
  -- HR-Feldauswahl pro Showcase (§11). Kann nur wegnehmen, nie hinzufügen
  -- (harte Grenze = Erlaubnisliste in cv_public_json). Default = die 12 Standardfelder.
  visible_fields text[] not null default array[
    'first_name','last_name','age','city','experience_years','language_level',
    'writing_level','languages_str','photo_url','photo_color','hobbies','favorite_food'
  ]::text[],
  created_at  timestamptz default now()
);
create index if not exists idx_showcases_project_id on public.showcases(project_id);
create index if not exists idx_showcases_token      on public.showcases(token);

-- Nachtrag (idempotent): visible_fields auch auf Bestandstabellen sicherstellen.
alter table public.showcases add column if not exists visible_fields text[] not null default array[
  'first_name','last_name','age','city','experience_years','language_level',
  'writing_level','languages_str','photo_url','photo_color','hobbies','favorite_food'
]::text[];


-- ----------------------------------------------------------------------------
-- 3) updated_at-Trigger für cvs (Funktion aus schema_auth.sql wiederverwendet)
-- ----------------------------------------------------------------------------
drop trigger if exists cvs_set_updated_at on public.cvs;
create trigger cvs_set_updated_at
  before update on public.cvs
  for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- 4) RLS: HR (management/hr/finance) Vollzugriff auf beide Tabellen.
--    Kunden bekommen KEINE Tabellen-Policy — Zugriff nur über RPCs (§6/§7).
-- ----------------------------------------------------------------------------
alter table public.cvs       enable row level security;
alter table public.showcases enable row level security;

drop policy if exists "HR full access cvs" on public.cvs;
create policy "HR full access cvs" on public.cvs
  for all to authenticated
  using (exists (select 1 from public.app_users
    where user_id = auth.uid() and role_keys && array['management','hr','finance']::text[]))
  with check (exists (select 1 from public.app_users
    where user_id = auth.uid() and role_keys && array['management','hr','finance']::text[]));

drop policy if exists "HR full access showcases" on public.showcases;
create policy "HR full access showcases" on public.showcases
  for all to authenticated
  using (exists (select 1 from public.app_users
    where user_id = auth.uid() and role_keys && array['management','hr','finance']::text[]))
  with check (exists (select 1 from public.app_users
    where user_id = auth.uid() and role_keys && array['management','hr','finance']::text[]));


-- ----------------------------------------------------------------------------
-- 5) Whitelist-Helper (§11): eine cvs-Zeile → öffentlich sichere Felder (jsonb),
--    gefiltert nach HR-Auswahl p_visible. Zwei Stufen:
--      1. ERLAUBNISLISTE = die hier gebauten Keys (harte Sicherheitsgrenze).
--      2. HR-Auswahl p_visible filtert daraus weg (kann nie hinzufügen).
--    → Geliefert wird Erlaubnisliste ∩ p_visible. Ein manipuliertes p_visible mit
--    'notes' läuft ins Leere, weil der Key gar nicht erst gebaut wird.
--    FEST GESPERRT (nie im Objekt): email, phone, notes, is_structured,
--    sales_potential, status, project_id, ai_reasoning, test_answers, extra,
--    better_email, better_phone.  id ist immer dabei (React-Key, nicht wählbar).
-- ----------------------------------------------------------------------------
create or replace function public.cv_public_json(c public.cvs, p_visible text[])
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object('id', c.id)
  || coalesce((
    select jsonb_object_agg(key, value)
    from jsonb_each(jsonb_build_object(
      'first_name',       c.first_name,
      'last_name',        c.last_name,
      'age',              c.age,
      'gender',           c.gender,
      'city',             c.city,
      'dialect',          c.dialect,
      'education',        c.education,
      'education_level',  c.education_level,
      'experience_years', c.experience_years,
      'work_history',     c.work_history,
      'language_level',   c.language_level,
      'writing_level',    c.writing_level,
      'languages_str',    c.languages_str,
      'homeoffice_pref',  c.homeoffice_pref,
      'available_from',   c.available_from,
      'dream',            c.dream,
      'travel_wish',      c.travel_wish,
      'hobbies',          c.hobbies,
      'favorite_food',    c.favorite_food,
      'photo_url',        c.photo_url,
      'photo_color',      c.photo_color,
      'audios',           c.audios,
      'videos',           c.videos,
      'test_scores',      c.test_scores
    ))
    where key = any(coalesce(p_visible, '{}'::text[]))   -- HR-Auswahl nimmt nur weg
  ), '{}'::jsonb);
$$;
revoke all on function public.cv_public_json(public.cvs, text[]) from public;


-- ----------------------------------------------------------------------------
-- 6) get_showcase(p_token) — öffentliche Detailseite (showcase.html), KEIN Login.
--    SECURITY DEFINER umgeht RLS, gibt NUR die Whitelist zurück. Token = Zugang.
-- ----------------------------------------------------------------------------
create or replace function public.get_showcase(p_token text)
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select case when s.id is null then null else jsonb_build_object(
    'project_id', s.project_id,
    'title',      s.title,
    'note',       s.note,
    'created_at', s.created_at,
    'candidates', coalesce((
      select jsonb_agg(public.cv_public_json(c, s.visible_fields))
      from public.cvs c where c.id = any(s.cv_ids)
    ), '[]'::jsonb)
  ) end
  from public.showcases s
  where s.token = p_token;
$$;
revoke all    on function public.get_showcase(text) from public;
grant execute on function public.get_showcase(text) to anon, authenticated;


-- ----------------------------------------------------------------------------
-- 7) list_my_showcases() — eingeloggtes Client-Portal (ShowcasesView).
--    Reuse get_my_client_project_id() (25e): auth.uid() → eigenes Projekt.
--    Gleiche Whitelist. Nicht-Kunden erhalten NULL-Projekt → leere Liste.
-- ----------------------------------------------------------------------------
create or replace function public.list_my_showcases()
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',         s.id,
    'title',      s.title,
    'note',       s.note,
    'token',      s.token,
    'created_at', s.created_at,
    'candidates', coalesce((
      select jsonb_agg(public.cv_public_json(c, s.visible_fields))
      from public.cvs c where c.id = any(s.cv_ids)
    ), '[]'::jsonb)
  ) order by s.created_at desc), '[]'::jsonb)
  from public.showcases s
  where s.project_id = public.get_my_client_project_id();
$$;
revoke all    on function public.list_my_showcases() from public;
grant execute on function public.list_my_showcases() to authenticated;


-- ----------------------------------------------------------------------------
-- 8) Realtime-Publication (WICHTIG: ohne das feuern keine postgres_changes für
--    cvs/showcases — der Kanal joined, empfängt aber nie Events). Muster wie
--    25a (employees/…) + 27a (payslips). Idempotent via IF NOT EXISTS.
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname='supabase_realtime' and schemaname='public' and tablename='cvs') then
    alter publication supabase_realtime add table public.cvs;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname='supabase_realtime' and schemaname='public' and tablename='showcases') then
    alter publication supabase_realtime add table public.showcases;
  end if;
end $$;


-- ----------------------------------------------------------------------------
-- 9) Dedup-Schutz für GDoc-Sync (4a-3): partielle unique-Indizes.
--    Echte Duplikate kollidieren hart (23505), leere/NULL bleiben erlaubt
--    (mehrere NULL sind zulaessig). Der Frontend-Bulk-Insert dedupt zusaetzlich
--    per JS-Vorfilterung; diese Indizes sind das Netz gegen Parallel-Sync.
-- ----------------------------------------------------------------------------
create unique index if not exists idx_cvs_phone_unique
  on public.cvs(phone) where phone is not null and phone <> '';
create unique index if not exists idx_cvs_email_unique
  on public.cvs(email) where email is not null and email <> '';


-- ----------------------------------------------------------------------------
-- 11) Alte 1-arg-Funktion droppen. Muss NACH dem RPC-Update laufen (§6/§7 rufen
--     jetzt die 2-arg-Variante) — sonst Abhängigkeitsfehler. Idempotent.
-- ----------------------------------------------------------------------------
drop function if exists public.cv_public_json(public.cvs);


-- ============================================================================
-- FERTIG. Danach: Frontend-Umbau (CVsView/RecruitingKanban/GDoc-Sync → sb.from
-- ('cvs'); client.html ShowcasesView → sb.rpc('list_my_showcases'); showcase.html
-- → sb.rpc('get_showcase',{p_token})). Eigener Umsetzungs-Schritt.
-- ============================================================================
