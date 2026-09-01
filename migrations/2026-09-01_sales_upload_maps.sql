-- Gemerkte Spalten-Zuordnung je Dateiart (Signatur = sortierte, normalisierte Spaltenüberschriften). Beim nächsten
-- Upload derselben Dateiart wird die Zuordnung automatisch vorgeschlagen. Geteilt im Akquise-Team (is_sales_user).
create table if not exists public.sales_upload_maps(
  signature text primary key,
  mapping jsonb not null default '{}'::jsonb,
  sample_headers text,
  updated_at timestamptz not null default now()
);
alter table public.sales_upload_maps enable row level security;
drop policy if exists sales_upload_maps_rw on public.sales_upload_maps;
create policy sales_upload_maps_rw on public.sales_upload_maps for all using (is_sales_user()) with check (is_sales_user());
grant select, insert, update, delete on public.sales_upload_maps to authenticated;
