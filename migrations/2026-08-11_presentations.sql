-- =============================================================================
-- Kundenpräsentationen — Schnitt 1: Datenmodell + Logo-Bucket + öffentliche RPC
-- =============================================================================
-- Wiederkehrende KPI-Berichte (KW oder Monat) je Projekt/Skill. Kennzahlen aus dem
-- System, Snapshot beim Erzeugen (rückwirkend stabil), Ausgabe als Link (Token) oder
-- Druck-PDF. Design/Render kommt als Code (Schnitt 3, wartet auf die Inhaltsvorlage).
--
-- Enthält auch die MONATS-Erweiterung von kpi_project_entries: manche Kunden nennen
-- Wochen-, manche Monatszahlen. Echte Monatszahl wenn vorhanden → genommen; sonst
-- Wochen-Mittel, im Bericht als "abgeleitet" gekennzeichnet (FX-Muster, Frontend).
-- Idempotent. Im Supabase SQL-Editor ausführen.
-- =============================================================================


-- ── A) kpi_project_entries: zusätzlich MONATS-Werte (kw ODER month, nie beides) ──
alter table public.kpi_project_entries
  add column if not exists month int;   -- 1..12 für Monatswerte; kw bleibt für Wochenwerte

do $$ begin
  if not exists (select 1 from pg_constraint where conname='kpi_project_entries_period_chk') then
    alter table public.kpi_project_entries
      add constraint kpi_project_entries_period_chk
      check ( (kw is not null and month is null) or (kw is null and month is not null) );
  end if;
end $$;

-- Monats-Eindeutigkeit (partiell; das bestehende kpi_project_entries_uniq deckt die Wochen ab).
create unique index if not exists kpi_project_entries_month_uniq
  on public.kpi_project_entries (project_id, skill, year, month, kpi_id) where month is not null;
create index if not exists idx_kpi_project_entries_month_lookup
  on public.kpi_project_entries (project_id, year, month) where month is not null;


-- ── B) Vorlagen (Aufbau einmal definiert: Layout-Code-Key + Slots + Logos/Kontakt) ──
create table if not exists public.presentation_templates (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null,
  layout_key         text not null default 'default',      -- welches Code-Layout (Design = Code, Schnitt 3)
  orientation        text not null default 'landscape',    -- landscape|portrait (PDF-Ausrichtung)
  project_id         text,                                 -- optional projektgebunden
  slots              jsonb not null default '{}'::jsonb,   -- KPI-Slots + Freitext-Slots (welche Zahl wo, wo Text)
  our_logo_path      text,                                 -- Storage-Pfad (Bucket presentation-assets)
  customer_logo_path text,
  contact_name       text,
  contact_email      text,
  contact_phone      text,
  created_by         text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint presentation_templates_orient_chk check (orientation in ('landscape','portrait'))
);
grant select, insert, update, delete on public.presentation_templates to authenticated;

alter table public.presentation_templates enable row level security;
drop policy if exists presentation_templates_admin_all on public.presentation_templates;
create policy presentation_templates_admin_all on public.presentation_templates
  for all to authenticated
  using      (public.is_admin())     -- management/hr; bei Bedarf später auf is_management() verengbar
  with check (public.is_admin());


-- ── C) Erzeugte Berichte (SNAPSHOT: Kennzahlen eingefroren + Freitext + Token) ──
create table if not exists public.presentations (
  id           uuid primary key default gen_random_uuid(),
  template_id  uuid references public.presentation_templates(id) on delete set null,
  project_id   text not null,
  skill        text,                                       -- optional Skill-Ebene
  period_type  text not null,                              -- kw|month
  period_year  int  not null,
  period_no    int  not null,                              -- KW (1..53) oder Monat (1..12)
  title        text,
  data         jsonb not null default '{}'::jsonb,         -- SNAPSHOT: KPI-Werte + derived-Flags + Freitext + Logo-/Kontakt-Kopie
  public_token text unique,                                -- Capability-Kennung (base62, ~22 Z.); null = nicht veröffentlicht
  published    boolean not null default false,
  expires_at   timestamptz,                                -- optional
  created_by   text,
  created_at   timestamptz not null default now(),
  constraint presentations_period_chk check (period_type in ('kw','month'))
);
create index if not exists idx_presentations_period on public.presentations (project_id, period_year, period_no);
create index if not exists idx_presentations_token  on public.presentations (public_token);
grant select, insert, update, delete on public.presentations to authenticated;

alter table public.presentations enable row level security;
-- Intern: management/hr voller Zugriff. KEINE anon-Policy → öffentlicher Zugriff NUR über die RPC unten.
drop policy if exists presentations_admin_all on public.presentations;
create policy presentations_admin_all on public.presentations
  for all to authenticated
  using      (public.is_admin())
  with check (public.is_admin());


-- ── D) Logo-Bucket (öffentlich lesbar — Logos auf der Login-freien Berichtseite) ──
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('presentation-assets', 'presentation-assets', true, 5242880,
        array['image/png','image/jpeg','image/svg+xml','image/webp'])
on conflict (id) do update
  set public             = true,
      file_size_limit    = 5242880,
      allowed_mime_types = array['image/png','image/jpeg','image/svg+xml','image/webp'];

-- Lesen: öffentlich (Bucket public=true). Schreiben/Ändern/Löschen: nur management/hr.
drop policy if exists "presentation_assets admin write" on storage.objects;
create policy "presentation_assets admin write" on storage.objects
  for all to authenticated
  using      (bucket_id = 'presentation-assets' and public.is_admin())
  with check (bucket_id = 'presentation-assets' and public.is_admin());


-- ── E) Öffentliche Auflösung per Token (SECURITY DEFINER; anon darf NUR das) ──
-- Gibt genau einen veröffentlichten, nicht abgelaufenen Bericht zum Token zurück.
-- Die presentations-Tabelle selbst ist für anon NICHT lesbar (keine anon-Policy) →
-- der Token ist der Schlüssel (Capability-URL), nicht erratbar/enumerierbar.
create or replace function public.get_public_presentation(p_token text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id',           p.id,
    'title',        p.title,
    'project_id',   p.project_id,
    'skill',        p.skill,
    'period_type',  p.period_type,
    'period_year',  p.period_year,
    'period_no',    p.period_no,
    'data',         p.data,
    'orientation',  coalesce(t.orientation,'landscape'),
    'layout_key',   coalesce(t.layout_key,'default'),
    'created_at',   p.created_at
  )
  from public.presentations p
  left join public.presentation_templates t on t.id = p.template_id
  where p.public_token = p_token
    and p.published = true
    and (p.expires_at is null or p.expires_at > now())
  limit 1;
$$;

revoke all    on function public.get_public_presentation(text) from public;
grant execute on function public.get_public_presentation(text) to anon, authenticated;


-- ── Verifikation (optional) ──────────────────────────────────────────────────
-- select column_name from information_schema.columns where table_name='kpi_project_entries' and column_name='month';
-- select id, public from storage.buckets where id='presentation-assets';   -- public=t
-- select public.get_public_presentation('nichtvorhanden');                  -- NULL (kein Leak)
-- select polname from pg_policy where polrelid='public.presentations'::regclass; -- 1 (admin_all)
