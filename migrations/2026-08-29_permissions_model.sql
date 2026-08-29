-- Rechte-Vorhaben Schnitt 1: Datenmodell + Resolver. REIN ADDITIV.
--   - Keine bestehende Policy/Tabelle wird angefasst.
--   - Nichts wird durchgesetzt (keine Policy liest perm()). Live-Verhalten bleibt identisch.
--   - Die Standards (role_permissions) bilden das HEUTIGE Verhalten nach:
--       * "sichtbar" ist exakt aus der Menü-Logik abgeleitet (menuRoleDefault in hr.html:
--         Lead-Cap LEAD_ALLOWED_TABS, Kosten-Views AI_COST_VIEWS nur management/finance,
--         HR_ALWAYS_TABS, Flag-Guards mgmt/mgmtHr/mgmtLead/overhead).
--       * "modus" = edit, wenn die Rolle die Kern-Tabelle des Bereichs laut RLS schreiben darf,
--         sonst read (Maximal-Fähigkeit -> beim späteren Scharfschalten geht nichts verloren).
--       * Ausschnitt aus den bestätigten Rollen-Standards + RLS.
--   - Nur die 5 HR-Portal-Rollen sind geseedet (management, hr, finance, projektleiter, teamlead).
--     qm/trainer/asp/mitarbeiter/kunde bleiben ungeseedet -> Resolver liefert unsichtbar
--     (qm/trainer heute kein HR-Portal; asp/mitarbeiter/kunde eigene Portale, später modelliert).

-- ── 1) Bereichs-Katalog (13) ─────────────────────────────────────────────────
create table if not exists public.permission_areas (
  key         text primary key,
  label       text not null,
  seq         int  not null,
  axes        jsonb not null default '{}'::jsonb,   -- {gehalt,projekt,skill,hierarchie}
  menu_keys   text[] not null default '{}'
);

insert into public.permission_areas(key,label,seq,axes,menu_keys) values
 ('emp','Mitarbeiter',1,'{"gehalt":true,"projekt":true,"skill":false,"hierarchie":true}','{employees,orgchart,skillmatrix,onboarding}'),
 ('bewerber','Bewerber',2,'{"gehalt":false,"projekt":true,"skill":false,"hierarchie":false}','{cvs,kanban,funnel,bewerberlinks,dubletten,cvsync,showcase}'),
 ('kpi','Kennzahlen & Qualität',3,'{"gehalt":false,"projekt":true,"skill":true,"hierarchie":true}','{performance,auswertung,fcist,forecast,callqa}'),
 ('shift','Schichten & Zeit',4,'{"gehalt":false,"projekt":true,"skill":true,"hierarchie":true}','{shiftplan,checkin,workforce,timetracking}'),
 ('absence','Abwesenheiten',5,'{"gehalt":false,"projekt":true,"skill":true,"hierarchie":true}','{absences,urlaubantraege}'),
 ('lohn','Lohn & Wirtschaftlichkeit',6,'{"gehalt":true,"projekt":true,"skill":false,"hierarchie":false}','{payroll,profitability,productivity}'),
 ('praesent','Präsentationen',7,'{"gehalt":false,"projekt":true,"skill":false,"hierarchie":false}','{praesentation}'),
 ('feedback','Feedback',8,'{"gehalt":false,"projekt":true,"skill":false,"hierarchie":true}','{feedback}'),
 ('meeting','Besprechungen',9,'{"gehalt":false,"projekt":true,"skill":false,"hierarchie":false}','{meetingnotes}'),
 ('kalender','Kalender',10,'{"gehalt":false,"projekt":true,"skill":false,"hierarchie":false}','{calendar}'),
 ('datenpflege','Datenpflege & Importe',11,'{"gehalt":false,"projekt":true,"skill":false,"hierarchie":false}','{dataimport,uploads,uploadplan,datacheck,recmkt}'),
 ('schulung','Schulung & Wissen',12,'{"gehalt":false,"projekt":true,"skill":false,"hierarchie":false}','{training_plans,timeline,elearning,knowledge,languagetest,test_editor,test_preview,wissen_system}'),
 ('system','System & Verwaltung',13,'{"gehalt":false,"projekt":false,"skill":false,"hierarchie":false}','{superadmin,appusers,aiaccess,whosees,hraccess,tabperms,activity_log,useractivity,reminders,taskadmin,projects,locations,spaces,cockpits}')
on conflict (key) do nothing;

-- ── 2) Rechte je Rolle (Standard) und je Person (Override) ──────────────────
create table if not exists public.role_permissions (
  role_key    text not null,
  area_key    text not null references public.permission_areas(key),
  visible     boolean not null default false,
  mode        text not null default 'none',      -- none|read|edit
  salary      text not null default 'none',      -- none|own|all
  direction   text not null default 'down',      -- down|side|up
  projects    text not null default 'own',       -- own|list|all
  project_ids text[] not null default '{}',
  skill       text not null default 'all',       -- own|all
  primary key (role_key, area_key)
);

create table if not exists public.user_permissions (
  user_id     uuid not null,
  area_key    text not null references public.permission_areas(key),
  visible     boolean not null default false,
  mode        text not null default 'none',
  salary      text not null default 'none',
  direction   text not null default 'down',
  projects    text not null default 'own',
  project_ids text[] not null default '{}',
  skill       text not null default 'all',
  updated_at  timestamptz not null default now(),
  primary key (user_id, area_key)
);

-- ── 3) Seed der Rollen-Standards (bildet heute nach) ────────────────────────
-- Spalten: role, area, visible, mode, salary, direction, projects, skill
insert into public.role_permissions(role_key,area_key,visible,mode,salary,direction,projects,skill) values
-- management: alles, bearbeiten, Gehalt alle, aufsteigend, alle Projekte/Skills
 ('management','emp',true,'edit','all','up','all','all'),
 ('management','bewerber',true,'edit','none','up','all','all'),
 ('management','kpi',true,'edit','none','up','all','all'),
 ('management','shift',true,'edit','none','up','all','all'),
 ('management','absence',true,'edit','none','up','all','all'),
 ('management','lohn',true,'edit','all','up','all','all'),
 ('management','praesent',true,'edit','none','up','all','all'),
 ('management','feedback',true,'edit','none','up','all','all'),
 ('management','meeting',true,'edit','none','up','all','all'),
 ('management','kalender',true,'edit','none','up','all','all'),
 ('management','datenpflege',true,'edit','none','up','all','all'),
 ('management','schulung',true,'edit','none','up','all','all'),
 ('management','system',true,'edit','none','up','all','all'),
-- hr: Personen/Bewerber/Abw./Feedback/Schulung bearbeiten, Gehalt alle (Mgmt bleibt maskiert),
--     Lohn&Wirtschaftlichkeit HEUTE nicht im Menü (Kosten-Views mgmt/finance-only) -> visible=false [FLAG]
 ('hr','emp',true,'edit','all','up','all','all'),
 ('hr','bewerber',true,'edit','none','up','all','all'),
 ('hr','kpi',true,'edit','none','up','all','all'),
 ('hr','shift',true,'edit','none','up','all','all'),
 ('hr','absence',true,'edit','none','up','all','all'),
 ('hr','lohn',false,'none','all','up','all','all'),
 ('hr','praesent',false,'none','none','up','all','all'),
 ('hr','feedback',true,'edit','none','up','all','all'),
 ('hr','meeting',false,'none','none','up','all','all'),
 ('hr','kalender',true,'edit','none','up','all','all'),
 ('hr','datenpflege',true,'read','none','up','all','all'),
 ('hr','schulung',true,'edit','none','up','all','all'),
 ('hr','system',true,'read','none','up','all','all'),
-- finance: Geld voll, sonst lesen; Menü heute breit (alle ungeschützten Punkte) [FLAG]
 ('finance','emp',true,'read','all','up','all','all'),
 ('finance','bewerber',true,'read','none','up','all','all'),
 ('finance','kpi',true,'read','none','up','all','all'),
 ('finance','shift',true,'read','none','up','all','all'),
 ('finance','absence',true,'read','none','up','all','all'),
 ('finance','lohn',true,'edit','all','up','all','all'),
 ('finance','praesent',false,'none','none','up','all','all'),
 ('finance','feedback',true,'read','none','up','all','all'),
 ('finance','meeting',false,'none','none','up','all','all'),
 ('finance','kalender',true,'read','none','up','all','all'),
 ('finance','datenpflege',true,'read','none','up','all','all'),
 ('finance','schulung',true,'read','none','up','all','all'),
 ('finance','system',true,'read','none','up','all','all'),
-- projektleiter: eigenes Projekt, gleiche Ebene (side), Overhead sichtbar, kein Gehalt
 ('projektleiter','emp',true,'edit','none','side','own','all'),
 ('projektleiter','bewerber',true,'edit','none','side','all','all'),
 ('projektleiter','kpi',true,'edit','none','side','own','all'),
 ('projektleiter','shift',true,'edit','none','side','own','all'),
 ('projektleiter','absence',true,'edit','none','side','own','all'),
 ('projektleiter','lohn',false,'none','none','side','own','all'),
 ('projektleiter','praesent',true,'edit','none','side','own','all'),
 ('projektleiter','feedback',true,'read','none','side','own','all'),
 ('projektleiter','meeting',false,'none','none','side','own','all'),
 ('projektleiter','kalender',true,'edit','none','side','own','all'),
 ('projektleiter','datenpflege',true,'edit','none','side','own','all'),
 ('projektleiter','schulung',false,'none','none','side','own','all'),
 ('projektleiter','system',false,'none','none','side','own','all'),
-- teamlead: eigenes Projekt + eigener Skill (bei kpi/shift/absence), absteigend, kein Gehalt
 ('teamlead','emp',true,'edit','none','down','own','all'),
 ('teamlead','bewerber',true,'edit','none','down','all','all'),
 ('teamlead','kpi',true,'edit','none','down','own','own'),
 ('teamlead','shift',true,'edit','none','down','own','own'),
 ('teamlead','absence',true,'edit','none','down','own','own'),
 ('teamlead','lohn',false,'none','none','down','own','all'),
 ('teamlead','praesent',true,'edit','none','down','own','all'),
 ('teamlead','feedback',true,'read','none','down','own','all'),
 ('teamlead','meeting',false,'none','none','down','own','all'),
 ('teamlead','kalender',true,'edit','none','down','own','all'),
 ('teamlead','datenpflege',true,'edit','none','down','own','all'),
 ('teamlead','schulung',false,'none','none','down','own','all'),
 ('teamlead','system',false,'none','none','down','own','all')
on conflict (role_key,area_key) do nothing;

-- ── 4) Resolver: Rolle-Standard (Vereinigung über mehrere Rollen) || Person-Override ──
create or replace function public.perm(p_uid uuid, p_area text)
returns jsonb language sql stable security definer set search_path=public as $$
  with ov as (select * from public.user_permissions where user_id=p_uid and area_key=p_area),
  rk as (select unnest(coalesce((select role_keys from public.app_users where user_id=p_uid),'{}'::text[])) as role_key),
  rd as (
    select
      bool_or(rp.visible) as visible,
      max(case rp.mode when 'edit' then 2 when 'read' then 1 else 0 end) as m,
      max(case rp.salary when 'all' then 2 when 'own' then 1 else 0 end) as sal,
      max(case rp.direction when 'up' then 2 when 'side' then 1 else 0 end) as dir,
      max(case rp.projects when 'all' then 2 when 'list' then 1 else 0 end) as prj,
      max(case rp.skill when 'all' then 1 else 0 end) as skl
    from public.role_permissions rp join rk on rk.role_key=rp.role_key where rp.area_key=p_area
  )
  select case when exists(select 1 from ov)
    then (select jsonb_build_object('visible',visible,'mode',mode,'salary',salary,'direction',direction,
            'projects',projects,'project_ids',project_ids,'skill',skill,'source','user') from ov)
    else (select jsonb_build_object(
            'visible', coalesce((select visible from rd),false),
            'mode', (array['none','read','edit'])[coalesce((select m from rd),0)+1],
            'salary', (array['none','own','all'])[coalesce((select sal from rd),0)+1],
            'direction', (array['down','side','up'])[coalesce((select dir from rd),0)+1],
            'projects', (array['own','list','all'])[coalesce((select prj from rd),0)+1],
            'project_ids', '{}'::text[],
            'skill', (array['own','all'])[coalesce((select skl from rd),0)+1],
            'source','role'))
  end;
$$;

-- Übersicht für die Admin-UI (Schnitt 2) + Verifikation. Nur Management. Je HR-Portal-Zugang die effektiven Rechte.
create or replace function public.permissions_overview()
returns jsonb language sql stable security definer set search_path=public as $$
  select case when not public.is_management() then '[]'::jsonb else (
    select coalesce(jsonb_agg(jsonb_build_object(
      'user_id', u.user_id, 'name', u.full_name, 'role_keys', u.role_keys,
      'areas', (select jsonb_object_agg(a.key, public.perm(u.user_id, a.key)) from public.permission_areas a)
    ) order by u.full_name), '[]'::jsonb)
    from public.app_users u
    where u.active and u.role_keys && array['management','hr','finance','teamlead','projektleiter']::text[]
  ) end;
$$;

-- ── 5) RLS: Katalog für alle lesbar, Rechte-Tabellen nur Management ──────────
alter table public.permission_areas enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_permissions enable row level security;

drop policy if exists permission_areas_read on public.permission_areas;
create policy permission_areas_read on public.permission_areas for select using (auth.role() = 'authenticated');
drop policy if exists role_permissions_mgmt on public.role_permissions;
create policy role_permissions_mgmt on public.role_permissions for all using (public.is_management()) with check (public.is_management());
drop policy if exists user_permissions_mgmt on public.user_permissions;
create policy user_permissions_mgmt on public.user_permissions for all using (public.is_management()) with check (public.is_management());

grant select on public.permission_areas to authenticated;
grant select, insert, update, delete on public.role_permissions to authenticated;
grant select, insert, update, delete on public.user_permissions to authenticated;
grant execute on function public.perm(uuid,text) to authenticated;
grant execute on function public.permissions_overview() to authenticated;
