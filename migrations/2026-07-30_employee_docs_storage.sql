-- =============================================================================
-- Dokumenten-Ablage — Schritt A (Fundament)
-- Arbeitsvertraege (PDF) + unterschriebenes Kuendigungsoriginal je Mitarbeiter.
-- Privater Storage-Bucket + Metadaten-Tabelle, beide mit identischer RLS:
--   management/hr sehen ALLES, der verknuepfte Mitarbeiter NUR sein Eigenes,
--   sonst NIEMAND. Fail-closed: kein Treffer => gesperrt (Deny-by-default).
-- Idempotent: kann erneut ausgefuehrt werden.
-- Im Supabase SQL-Editor ausfuehren (als privilegierter Rolle).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1) Privater Bucket. public=false wird ERZWUNGEN (auch falls er schon existiert).
--    Limits: max 10 MB pro Datei, nur application/pdf.
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('employee-docs', 'employee-docs', false, 10485760, array['application/pdf'])
on conflict (id) do update
  set public             = false,
      file_size_limit    = 10485760,
      allowed_mime_types = array['application/pdf'];


-- -----------------------------------------------------------------------------
-- 2) Helper: eigene employee_id des eingeloggten Users.
--    SECURITY DEFINER -> umgeht RLS auf app_users, deterministisch.
--    Liefert NULL, wenn der User keine app_users-Zeile hat ODER nicht mit
--    einem Mitarbeiter verknuepft ist. NULL => jeder Vergleich schlaegt fehl
--    => Zugriff gesperrt (das ist die fail-closed-Grundlage).
-- -----------------------------------------------------------------------------
create or replace function public.my_employee_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select employee_id
  from public.app_users
  where user_id = auth.uid()
  limit 1;
$$;

revoke all    on function public.my_employee_id() from public;
grant execute on function public.my_employee_id() to authenticated;


-- -----------------------------------------------------------------------------
-- 3) Metadaten-Tabelle: eine Zeile pro abgelegtem Dokument.
--    Storage haelt nur die Bytes; hier stehen Typ, Originalname, Groesse,
--    wer/wann hochgeladen. storage_path ist der Bezug zum Bucket-Objekt.
-- -----------------------------------------------------------------------------
create table if not exists public.employee_documents (
  id            uuid primary key default gen_random_uuid(),
  employee_id   uuid not null references public.employees(id) on delete cascade,
  doc_type      text not null check (doc_type in ('contract','termination')),
  storage_path  text not null unique,          -- z.B. '<employee_id>/contract/2026-07-30_...pdf'
  original_name text,
  size_bytes    bigint,
  mime_type     text default 'application/pdf',
  uploaded_by   uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now()
);

create index if not exists idx_employee_documents_employee_id on public.employee_documents(employee_id);

grant select, insert, update, delete on public.employee_documents to authenticated;


-- -----------------------------------------------------------------------------
-- 4) RLS auf der Metadaten-Tabelle. Deny-by-default; nur diese zwei Policies
--    oeffnen etwas. Keine Zeile => kein Zugriff.
-- -----------------------------------------------------------------------------
alter table public.employee_documents enable row level security;

-- management/hr: voller Zugriff (lesen/schreiben/loeschen)
drop policy if exists employee_documents_admin_all on public.employee_documents;
create policy employee_documents_admin_all
  on public.employee_documents
  for all
  to authenticated
  using      (public.is_admin())
  with check (public.is_admin());

-- Mitarbeiter: NUR eigene Zeilen LESEN. Kein insert/update/delete (das macht HR).
-- my_employee_id() = NULL (unverknuepft) => employee_id = NULL => nicht wahr => gesperrt.
drop policy if exists employee_documents_select_own on public.employee_documents;
create policy employee_documents_select_own
  on public.employee_documents
  for select
  to authenticated
  using (employee_id = public.my_employee_id());


-- -----------------------------------------------------------------------------
-- 5) RLS auf storage.objects, ausschliesslich fuer den Bucket 'employee-docs'.
--    storage.objects hat RLS bei Supabase bereits aktiv. Diese Policies sind
--    additiv (mit ODER verknuepft) — deshalb jede strikt auf den Bucket
--    eingegrenzt, damit sie NUR hier greifen und nichts anderes oeffnen.
--    Der RLS-Anker ist der erste Pfad-Ordner = employee_id:
--      (storage.foldername(name))[1]  ->  '<employee_id>'
-- -----------------------------------------------------------------------------

-- management/hr: voller Zugriff auf den Bucket (lesen/hochladen/aendern/loeschen)
drop policy if exists "employee_docs admin all" on storage.objects;
create policy "employee_docs admin all"
  on storage.objects
  for all
  to authenticated
  using      (bucket_id = 'employee-docs' and public.is_admin())
  with check (bucket_id = 'employee-docs' and public.is_admin());

-- Mitarbeiter: NUR den eigenen Ordner LESEN. Kein Upload/Delete.
-- Root-Datei ohne Ordner => [1] ist NULL => gesperrt. Unverknuepft => NULL => gesperrt.
drop policy if exists "employee_docs read own" on storage.objects;
create policy "employee_docs read own"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'employee-docs'
    and (storage.foldername(name))[1] = public.my_employee_id()::text
  );


-- =============================================================================
-- FERTIG. Danach die drei PRUEF-Bloecke unten laufen (separat, nicht Teil der
-- Migration) — sie belegen: Bucket privat, keine breiten Fremd-Policies,
-- und ein Kollege kommt an fremde Dokumente NICHT heran.
-- =============================================================================
