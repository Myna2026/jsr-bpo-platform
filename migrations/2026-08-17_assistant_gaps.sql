-- Lücken-Report des Wissens-Assistenten: unbeantwortete Fragen (Assistent: "weiß ich nicht").
-- Insert erfolgt serverseitig aus der Edge Function (Service-Role). Lesen/Erledigen: HR + Management.
create table if not exists public.assistant_gaps (
  id         uuid primary key default gen_random_uuid(),
  question   text not null,
  asked_by   uuid,
  resolved   boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.assistant_gaps enable row level security;

drop policy if exists assistant_gaps_sel on public.assistant_gaps;
create policy assistant_gaps_sel on public.assistant_gaps for select to authenticated
  using ( public.is_admin() );
drop policy if exists assistant_gaps_upd on public.assistant_gaps;
create policy assistant_gaps_upd on public.assistant_gaps for update to authenticated
  using ( public.is_admin() ) with check ( public.is_admin() );
drop policy if exists assistant_gaps_del on public.assistant_gaps;
create policy assistant_gaps_del on public.assistant_gaps for delete to authenticated
  using ( public.is_admin() );

grant select, update, delete on public.assistant_gaps to authenticated;
