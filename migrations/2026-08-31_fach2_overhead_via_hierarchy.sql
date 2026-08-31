-- Fachentscheidung 2 (User 2026-08-30): Projektleiter sehen Overhead + Gleichrangige im EIGENEN Projekt, in App
-- UND KI. Heute: die App zeigt es (perm_proj_ok, nur Projekt), die KI verbarg Overhead (perm_overhead_ok-Block in
-- perm_emp_row_ok). Angleichen ÜBER DIE HIERARCHIE-ACHSE, keine fünfte Achse: den Overhead-Kategorie-Block aus
-- perm_emp_row_ok ENTFERNEN → nur noch der Rang gilt. Projektleiter (Rang 40, dir=side) sieht Rang <=40 (Overhead
-- Rang 30, Gleichrangige Rang 40), NICHT Management (Rang 100). Damit fällt Hajrijes Ein-Personen-Ausnahme weg.
-- Betrifft NUR die KI (ai_scoped nutzt perm_emp_row_ok); die App nutzt perm_proj_ok und war schon so.

begin;

-- Hajrijes temporäre Ausnahme raus: perm_overhead_ok = sauber mgmt/finance/hr (nur noch von der whosees-Anzeige genutzt).
create or replace function public.perm_overhead_ok(p_uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.app_users
                where user_id=p_uid and active and role_keys && array['management','finance','hr']::text[])
$$;

-- Overhead-Kategorie-Block entfernt; Sichtbarkeit läuft jetzt allein über Projekt + Skill + Hierarchie/Richtung.
create or replace function public.perm_emp_row_ok(p_uid uuid, p_area text, p_emp_id uuid, p_project text, p_skill text, p_position text)
returns boolean language plpgsql stable security definer set search_path=public as $$
declare crank int; rrank int; dir text;
begin
  if p_emp_id is not null and p_emp_id = public.perm_caller_emp_id(p_uid) then return true; end if;  -- eigene Zeile immer
  if not public.perm_proj_ok(p_uid, p_area, p_project, p_skill) then return false; end if;
  crank := public.perm_caller_rank(p_uid);
  rrank := public.ai_position_rank(p_position);
  dir  := coalesce(public.perm(p_uid,p_area)->>'direction','down');
  if rrank > crank and dir <> 'up'  then return false; end if;   -- höher sehen nur bei 'up'
  if rrank = crank and dir =  'down' then return false; end if;   -- 'down' ohne gleiche Ebene
  return true;
end $$;

commit;

-- ── ROLLBACK (manuell) ──
-- create or replace function public.perm_overhead_ok(p_uid uuid default auth.uid())
-- returns boolean language sql stable security definer set search_path=public as $$
--   select exists(select 1 from public.app_users where user_id=p_uid and active and role_keys && array['management','finance','hr']::text[])
--      and p_uid is distinct from '36e00596-2162-4885-a8d1-759dfe582bb7'::uuid $$;
-- (perm_emp_row_ok mit der Zeile davor wiederherstellen: nach dem perm_proj_ok-Check einfügen:
--  if not public.perm_overhead_ok(p_uid) and public.ai_position_category(p_position) in ('admin','overhead') then return false; end if;)
