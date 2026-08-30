-- Rechte Schnitt 5, Teil 1: Seeds/Overrides/overhead-Regel EXAKT aufs IST (altes ai) ausrichten,
-- bevor die KI (ai_scoped) auf perm_* umgestellt wird. Nur Datenachsen (direction/salary), visible unberührt
-- (Schnitt-3-Menü-Parität bleibt). Alle Werte = ai_default_prefs/ai_access_prefs (IST), KEINE Soll-Änderung.

-- A) Seed-Korrektur aufs IST: mgmt/finance/hr direction=side (war fälschlich up), hr Gehalt=none (war fälschlich all).
--    Das "hr Gehalt alle" war die SOLL-Vorgabe, gehört bewusst/sichtbar gemacht (Fachentscheidungs-Liste), nicht als Seed.
update public.role_permissions set direction='side'
  where role_key in ('management','finance','hr') and direction='up';
update public.role_permissions set salary='none'
  where role_key='hr' and salary is distinct from 'none';
-- bewerber: projektleiter/teamlead Seed war 'all' (die SOLL-Absicht „projekt○ = alle Bewerber"), IST (altes ai) ist
-- global 'own'. Aufs IST: 'own'. Ob Leads alle Bewerber sehen sollen, ist eine Fachentscheidung (Recruiting).
update public.role_permissions set projects='own'
  where role_key in ('projektleiter','teamlead') and area_key='bewerber' and projects='all';

-- B) ai_access_prefs-Overrides nach user_permissions migrieren (eine Wahrheit). Nach dem Seed-Fix (projects=own
--    für Leads überall) unterscheidet sich der IST-Override nur noch in EINER Achse: direction=down. Ylli und
--    Hajrije haben direction=down (statt side); nur in den Hierarchie-Bereichen (emp/kpi/shift) wirksam. Edi hat
--    side/own = Rollen-Default → kein Eintrag nötig. Rows kopieren den Rollen-Default, überschreiben nur direction.
insert into public.user_permissions(user_id, area_key, visible, mode, salary, direction, projects, project_ids, skill)
select u.uid, rp.area_key, rp.visible, rp.mode, rp.salary, 'down', rp.projects, rp.project_ids, rp.skill
from (values
  ('312020fc-5857-4591-9a1c-f963700053b1'::uuid,'projektleiter'),   -- Ylli
  ('36e00596-2162-4885-a8d1-759dfe582bb7'::uuid,'hr')               -- Hajrije
) u(uid, role)
join public.role_permissions rp on rp.role_key=u.role and rp.area_key in ('emp','kpi','shift')
on conflict (user_id, area_key) do update set direction='down';

-- C) overhead-Regel (dokumentierte IST-Reproduktion, KEINE Taxonomie-Achse). Nur Management/Finance/HR sehen die
--    Overhead-/Admin-Kategorien (altes ai overhead_mgmt=true). AUSNAHME: Hajrije hatte per ai-Override overhead=false.
--    Ein Nutzer explizit in der Regel ist hässlich, aber exakt; verschwindet mit der overhead-Fachentscheidung
--    (dann echte Achse oder an der Hierarchie). Siehe Fachentscheidungs-Liste.
create or replace function public.perm_overhead_ok(p_uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.app_users
                where user_id=p_uid and active and role_keys && array['management','finance','hr']::text[])
     and p_uid is distinct from '36e00596-2162-4885-a8d1-759dfe582bb7'::uuid   -- AUSNAHME Hajrije (IST-Override), TEMPORÄR
$$;
grant execute on function public.perm_overhead_ok(uuid) to authenticated;

-- perm_emp_row_ok um die overhead-Prüfung ergänzen (nach eigener Zeile + Projekt, wie im alten ai).
create or replace function public.perm_emp_row_ok(p_uid uuid, p_area text, p_emp_id uuid, p_project text, p_skill text, p_position text)
returns boolean language plpgsql stable security definer set search_path=public as $$
declare crank int; rrank int; dir text;
begin
  if p_emp_id is not null and p_emp_id = public.perm_caller_emp_id(p_uid) then return true; end if;  -- eigene Zeile immer
  if not public.perm_proj_ok(p_uid, p_area, p_project, p_skill) then return false; end if;
  -- Overhead-/Admin-Kategorien nur für Overhead-berechtigte (IST-Regel, s.o.). null-Position = Kategorie 'admin'.
  if not public.perm_overhead_ok(p_uid) and public.ai_position_category(p_position) in ('admin','overhead') then return false; end if;
  crank := public.perm_caller_rank(p_uid);
  rrank := public.ai_position_rank(p_position);
  dir  := coalesce(public.perm(p_uid,p_area)->>'direction','down');
  if rrank > crank and dir <> 'up'  then return false; end if;   -- höher sehen nur bei 'up'
  if rrank = crank and dir =  'down' then return false; end if;   -- 'down' ohne gleiche Ebene
  return true;
end $$;
