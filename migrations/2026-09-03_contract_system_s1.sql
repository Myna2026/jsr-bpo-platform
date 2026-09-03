-- Vertrags-System, Schnitt 1: Fundament (Datenmodell + Storage). Weg B: die Vorlage ist ein HTML-Template mit
-- {{Platzhaltern}} (fixe Klauseln + variable Stellen), gerendert zu PDF. Das hochgeladene Original-PDF liegt als
-- Referenz im Storage. Verträge je Mitarbeiter sind Instanzen mit ausgefüllten Feldern und Status-Kreislauf
-- (Entwurf → verschickt → unterschrieben). Generierte/unterschriebene PDFs landen im vorhandenen employee-docs-
-- Bucket (doc_type='contract'), NICHT base64 in der Zeile (Lehre aus der Lade-Performance). Idempotent.

-- 1) Bucket für Vorlagen-Original-PDFs (Referenz), privat, nur Admin. Getrennt von employee-docs (nicht MA-bezogen).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('contract-templates','contract-templates', false, 10485760, array['application/pdf'])
on conflict (id) do update set public=false, file_size_limit=10485760, allowed_mime_types=array['application/pdf'];

drop policy if exists "contract_templates_bucket_admin" on storage.objects;
create policy "contract_templates_bucket_admin" on storage.objects for all to authenticated
  using      (bucket_id='contract-templates' and public.is_admin())
  with check (bucket_id='contract-templates' and public.is_admin());

-- 2) Vorlagen. body_html = fixer Text + {{key}}-Platzhalter. placeholders = Definition je Platzhalter inkl.
--    Mapping auf ein Mitarbeiterfeld (für die spätere Übernahme). kind/language für mehrere Fassungen.
create table if not exists public.contract_templates (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null,
  contract_kind      text not null default 'unbefristet' check (contract_kind in ('befristet','unbefristet')),
  language           text not null default 'sq' check (language in ('sq','de','en')),
  body_html          text,                              -- HTML-Template mit {{platzhalter}}
  reference_pdf_path text,                              -- Original-PDF im Bucket contract-templates
  placeholders       jsonb not null default '[]'::jsonb,-- [{key,label,type,maps_to,required}]
  active             boolean not null default true,
  created_by         uuid references auth.users(id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

-- 3) Vertrag je Mitarbeiter (Instanz). template_id NULL erlaubt = extern erstellter, manuell hochgeladener Vertrag.
--    status-Kreislauf. generated_* = im System erzeugt, signed_* = unterschriebenes Original (auch manueller Weg).
create table if not exists public.employee_contracts (
  id                 uuid primary key default gen_random_uuid(),
  employee_id        uuid not null references public.employees(id) on delete cascade,
  template_id        uuid references public.contract_templates(id) on delete set null,
  field_values       jsonb not null default '{}'::jsonb,
  status             text not null default 'draft' check (status in ('draft','sent','signed','archived','manual')),
  generated_pdf_path text,                              -- employee-docs: im System erzeugtes PDF
  signed_pdf_path    text,                              -- employee-docs: unterschriebenes Original
  sent_at            timestamptz,
  signed_at          timestamptz,
  applied_at         timestamptz,                       -- wann die Daten am Mitarbeiter übernommen wurden
  note               text,
  created_by         uuid references auth.users(id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index if not exists idx_employee_contracts_emp on public.employee_contracts(employee_id, status);

-- 4) RLS: Verträge sind sensibel → nur management/hr (is_admin). MA-Sicht auf das eigene unterschriebene PDF läuft
--    weiter über employee_documents (own-read); die Instanz-/Feldwerte bleiben HR-intern.
alter table public.contract_templates  enable row level security;
alter table public.employee_contracts  enable row level security;
drop policy if exists contract_templates_admin on public.contract_templates;
create policy contract_templates_admin on public.contract_templates for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
drop policy if exists employee_contracts_admin on public.employee_contracts;
create policy employee_contracts_admin on public.employee_contracts for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
grant select, insert, update, delete on public.contract_templates, public.employee_contracts to authenticated;
