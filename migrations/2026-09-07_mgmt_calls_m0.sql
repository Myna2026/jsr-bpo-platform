-- Management-Calls M0: Zugang (eigene Freigabeliste, DB-durchgesetzt) + Datenmodell + Bereiche-Config.
-- Projektunabhängig und vertraulich: nur die vier auf der Liste sehen/schreiben etwas (RLS). Muster wie Akquise
-- (sales_access / is_sales_user). In Management-Calls stehen Dinge, die nicht für alle sind.

-- ── Freigabeliste + Prüf-Funktion ───────────────────────────────────────────
create table if not exists public.mgmt_call_access (
  user_id  uuid primary key,
  added_at timestamptz not null default now()
);
insert into public.mgmt_call_access(user_id) values
  ('14a5001c-9efb-4f76-b8f8-145e24b4be5f'),   -- Rajner Gore
  ('b7cbd0b3-961d-41e2-b358-cc13806b3fe3'),   -- Thorsten Schröppe
  ('54f067ab-b6f8-47a1-afa7-6dcb86b89b29'),   -- Shkurte
  ('939dfd7c-f4ba-4a9e-aa2f-b3048544bffc')    -- Admin Test (admin@tive360.de)
on conflict do nothing;

create or replace function public.is_mgmt_call_user()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.mgmt_call_access where user_id = auth.uid())
$$;
grant execute on function public.is_mgmt_call_user() to authenticated;

-- ── Calls (ein Protokoll je Call) ───────────────────────────────────────────
create table if not exists public.mgmt_calls (
  id             uuid primary key default gen_random_uuid(),
  call_date      date not null,
  title          text,
  body           text,                    -- eingefügtes/getipptes Protokoll
  created_by     uuid,
  created_by_name text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists mgmt_calls_date_idx on public.mgmt_calls(call_date desc);

-- ── Offene Punkte je Call (Wer/was/bis wann + Bereich + Wiedervorlage) ───────
create table if not exists public.mgmt_call_items (
  id              uuid primary key default gen_random_uuid(),
  call_id         uuid references public.mgmt_calls(id) on delete set null,  -- Punkt überlebt Call-Löschung
  bereich         text,                   -- Personal/Recruiting/Projekte/Kunden/Finanzen/System (KI-zugeordnet, anpassbar)
  topic           text,                   -- kurzes Thema (optional)
  text            text not null,          -- die Aufgabe / der Punkt
  owner           text,                   -- Wer
  due_date        date,                   -- bis wann
  status          text not null default 'open',   -- open | done
  done_at         timestamptz,
  carried_from_call_id uuid,              -- Herkunft bei Wiedervorlage (M2)
  seq             int not null default 0,
  created_by      uuid,
  created_by_name text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists mgmt_call_items_call_idx on public.mgmt_call_items(call_id);
create index if not exists mgmt_call_items_open_idx on public.mgmt_call_items(status) where status='open';
create index if not exists mgmt_call_items_bereich_idx on public.mgmt_call_items(bereich);

-- ── RLS: alles nur für die Freigabeliste ────────────────────────────────────
do $$ declare t text;
begin
  foreach t in array array['mgmt_call_access','mgmt_calls','mgmt_call_items'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I_mc on public.%I', t, t);
    execute format('create policy %I_mc on public.%I for all to authenticated using (public.is_mgmt_call_user()) with check (public.is_mgmt_call_user())', t, t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;

-- ── Bereiche-Config (anpassbar) ─────────────────────────────────────────────
insert into public.app_config (key, value) values
  ('jsr_mgmt_bereiche_v1', '{"bereiche":["Personal","Recruiting","Projekte","Kunden","Finanzen","System"]}'::jsonb)
on conflict (key) do nothing;
