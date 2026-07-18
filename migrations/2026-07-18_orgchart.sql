-- =============================================================================
-- Organigramm: localStorage (jsr_org_v1) -> Supabase   2026-07-18
-- =============================================================================
-- Etappe O1: NUR SCHEMA + RLS. Noch NICHT im Frontend verdrahtet (eigene Etappe).
--
-- Reales Persistenz-Modell (OrgChart, hr.html setOrgCharts 6957 / addChildNode 6971):
--   {project_id: { id, rootId, auto_built, nodes:[
--       {id, title, subtitle, color, skill, employees:[emp_id,...], children:[nodeId,...]}
--   ]}}
-- -> hierarchischer Node-Baum (NICHT das flache roles-Legacy-Seed aus ORG_CHART_INIT).
--
-- Abbildung: eine Zeile pro Node in org_nodes.
--   - children[] -> parent_id (self-ref FK; null = Root, ersetzt rootId, ableitbar).
--   - employees[] (mehrere MA pro Node) -> jsonb (robuster als uuid[]: kein
--     Typ-Coercion-Fehler beim Schreiben, toleriert Legacy-IDs vor der MA-Migration).
--   - auto_built: text — das Frontend schreibt ein Datum-String (YYYY-MM-DD),
--     der 1:1 erhalten bleibt (kein Mapping-Verlust).
--
-- RLS nach projects-Muster: "read internal" (ALLE internen Rollen inkl. mitarbeiter,
-- Organigramm ist nicht vertraulich) + "HR write" (management/hr/finance).
--
-- Idempotent (create table / index / policy IF (NOT) EXISTS + drop policy if exists).
-- Anzuwenden im Supabase SQL Editor (hier NICHT ausgefuehrt).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1 Tabelle
-- -----------------------------------------------------------------------------
create table if not exists public.org_nodes (
  id          uuid primary key default gen_random_uuid(),
  project_id  text references public.projects(id) on delete cascade,
  parent_id   uuid references public.org_nodes(id) on delete cascade,   -- null = Root
  title       text,
  subtitle    text,
  color       text,
  skill       text,
  employees   jsonb default '[]'::jsonb,      -- [emp_id, ...] (mehrere MA je Node)
  seq         integer,
  auto_built  text,                          -- Datum-String vom Frontend (YYYY-MM-DD), 1:1
  created_at  timestamptz default now()
);
create index if not exists idx_org_nodes_project on public.org_nodes(project_id);
create index if not exists idx_org_nodes_parent  on public.org_nodes(parent_id);


-- -----------------------------------------------------------------------------
-- §2 RLS — read internal (alle internen Rollen inkl. mitarbeiter) + HR write
-- -----------------------------------------------------------------------------
alter table public.org_nodes enable row level security;
drop policy if exists "org_nodes read all authenticated" on public.org_nodes;
drop policy if exists "org_nodes read internal" on public.org_nodes;
drop policy if exists "org_nodes HR write" on public.org_nodes;

create policy "org_nodes read internal" on public.org_nodes
  for select to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance','teamlead','projektleiter','mitarbeiter']));

create policy "org_nodes HR write" on public.org_nodes
  for all to authenticated
  using (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']))
  with check (exists (select 1 from app_users where user_id = auth.uid()
         and role_keys && array['management','hr','finance']));


-- =============================================================================
-- Verifikation (auskommentiert)
-- =============================================================================
-- (a) Tabelle + Spalten (erwartet 11):
--     select count(*) from information_schema.columns
--      where table_schema='public' and table_name='org_nodes';           -- 11
-- (b) RLS + 2 Policies:
--     select c.relname, count(p.polname) from pg_class c
--      left join pg_policy p on p.polrelid=c.oid
--      where c.relname='org_nodes' group by c.relname;                    -- 2
-- (c) 2 FKs (project_id -> projects cascade, parent_id -> org_nodes cascade):
--     select conname, confdeltype from pg_constraint
--      where conrelid='public.org_nodes'::regclass and contype='f';       -- 2x 'c'
-- =============================================================================
