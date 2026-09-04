-- Postfach-Anhänge (empfangen + senden) für die geteilten Funktions-Postfächer.
-- Privater Bucket + Metadaten-Tabelle. Empfang: mail-fetch (service role) lädt Zoho-Anhänge in den Bucket.
-- Senden: Frontend lädt Datei in den Bucket, mail-reply hängt sie an die Zoho-Mail. RLS: Management/HR.
insert into storage.buckets (id, name, public, file_size_limit)
values ('mail-attachments','mail-attachments', false, 26214400)
on conflict (id) do update set public=false, file_size_limit=26214400;

create table if not exists public.mail_attachments (
  id uuid primary key default gen_random_uuid(),
  message_id uuid references public.mail_messages(id) on delete cascade,
  direction text, name text, size_bytes bigint, mime_type text, storage_path text not null,
  created_at timestamptz default now());
create index if not exists mail_attachments_msg on public.mail_attachments(message_id);
alter table public.mail_attachments enable row level security;
drop policy if exists mailatt_select on public.mail_attachments;
create policy mailatt_select on public.mail_attachments for select to authenticated using (public.is_management() or public.is_hr());

-- Storage-Policies: Management/HR dürfen lesen (signierte Links) und hochladen (Senden). Empfang läuft über service role.
drop policy if exists mailatt_obj_read on storage.objects;
create policy mailatt_obj_read on storage.objects for select to authenticated using (bucket_id='mail-attachments' and (public.is_management() or public.is_hr()));
drop policy if exists mailatt_obj_insert on storage.objects;
create policy mailatt_obj_insert on storage.objects for insert to authenticated with check (bucket_id='mail-attachments' and (public.is_management() or public.is_hr()));
