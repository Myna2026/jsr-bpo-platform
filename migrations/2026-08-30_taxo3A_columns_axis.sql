-- Taxonomie-Zuschnitt, Punkt 3 (eigener Schnitt), SCHRITT A: Personendaten-Spaltenstufe als Modell-Achse.
-- ECHTER FUND (User): „hr sieht Personal-/Vertragsdaten, Leads nur Operatives" war keine der 4 Achsen. Neue Achse
-- `columns` (operativ < personal < voll) für den Mitarbeiter-Bereich, damit die Spaltenmaskierung in employees_masked
-- nicht mehr fest verdrahtet ist (is_management/is_hr), sondern aus dem Modell kommt.
--   operativ = nur Betriebsdaten (Name/Position/Projekt/Schichten/Skills), kein Gehalt/Bank/Vertrag  → Leads
--   personal = zusätzlich Personal-/Vertragsdaten (Bank/Vertrag/Ausweis/persönlich), ABER kein Gehalt   → (künftig)
--   voll     = alles inkl. Gehalt                                                                       → mgmt/finance/hr
-- Gehalt bleibt zusätzlich über die Gehalt-Achse gesteuert; is_protected_employee (GF-Schutz) bleibt Row-Regel im View.
-- Schritt A: nur Schema + Resolver + Seeds (bildet IST ab). View-Umbau = Schritt B, RechteView = Schritt C.

begin;

alter table public.role_permissions add column if not exists columns text not null default 'operativ';
alter table public.user_permissions add column if not exists columns text;

-- Seeds aufs IST: mgmt/finance/hr sehen die vollen Spalten (hr mit GF-Schutz via is_protected_employee im View),
-- Leads/Teamleiter nur operativ. Andere Bereiche: 'operativ' (Default, irrelevant, nur emp maskiert Spalten).
update public.role_permissions set columns='voll'
  where area_key='emp' and role_key in ('management','finance','hr');
update public.role_permissions set columns='operativ'
  where area_key='emp' and role_key in ('projektleiter','teamlead');

-- Achse für die Rechte-Ansicht sichtbar machen (nur emp trägt sie).
update public.permission_areas
  set axes = axes || '{"columns": true}'::jsonb
  where key='emp';

-- Resolver perm() um 'columns' erweitern (Rollen-Union nimmt die höchste Stufe; Override zieht durch).
create or replace function public.perm(p_uid uuid, p_area text)
 returns jsonb language sql stable security definer set search_path to 'public'
as $function$
  with ov as (select * from public.user_permissions where user_id=p_uid and area_key=p_area),
  rk as (select unnest(coalesce((select role_keys from public.app_users where user_id=p_uid),'{}'::text[])) as role_key),
  rd as (
    select
      bool_or(rp.visible) as visible,
      max(case rp.mode when 'edit' then 2 when 'read' then 1 else 0 end) as m,
      max(case rp.salary when 'all' then 2 when 'own' then 1 else 0 end) as sal,
      max(case rp.direction when 'up' then 2 when 'side' then 1 else 0 end) as dir,
      max(case rp.projects when 'all' then 2 when 'list' then 1 else 0 end) as prj,
      max(case rp.skill when 'all' then 1 else 0 end) as skl,
      max(case rp.columns when 'voll' then 2 when 'personal' then 1 else 0 end) as col
    from public.role_permissions rp join rk on rk.role_key=rp.role_key where rp.area_key=p_area
  )
  select case when exists(select 1 from ov)
    then (select jsonb_build_object('visible',visible,'mode',mode,'salary',salary,'direction',direction,
            'projects',projects,'project_ids',project_ids,'skill',skill,
            'columns',coalesce(columns,'operativ'),'source','user') from ov)
    else (select jsonb_build_object(
            'visible', coalesce((select visible from rd),false),
            'mode', (array['none','read','edit'])[coalesce((select m from rd),0)+1],
            'salary', (array['none','own','all'])[coalesce((select sal from rd),0)+1],
            'direction', (array['down','side','up'])[coalesce((select dir from rd),0)+1],
            'projects', (array['own','list','all'])[coalesce((select prj from rd),0)+1],
            'project_ids', '{}'::text[],
            'skill', (array['own','all'])[coalesce((select skl from rd),0)+1],
            'columns', (array['operativ','personal','voll'])[coalesce((select col from rd),0)+1],
            'source','role'))
  end;
$function$;

commit;

-- ── ROLLBACK (manuell) ──
-- (perm() ohne 'columns' aus git wiederherstellen)
-- update public.permission_areas set axes = axes - 'columns' where key='emp';
-- alter table public.role_permissions drop column if exists columns;
-- alter table public.user_permissions drop column if exists columns;
