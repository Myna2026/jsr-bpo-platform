-- Fachentscheidung 2, Nachschärfung (User 2026-08-31):
-- (1) DEFENSIV: positionslose MA nicht mehr als unterste Ebene (Rang 15) behandeln → im Zweifel verbergen.
--     In perm_emp_row_ok bekommt eine NULL/leere Position einen hohen Rang (999), also für Leads verborgen
--     (nur „nach oben"/eigene Zeile sichtbar). Wer keine Position hat, wird nicht automatisch mitgezeigt.
-- (2) Ylli: eigentliches Problem ist die falsche Position (als Teamleiter eingetragen, ist aber Projektleiter).
--     Position korrigieren (statt einen Richtungs-Override zu setzen) → über den Rollen-Standard (dir=side) sieht
--     er sein Giganetz-Team vollständig inkl. Overhead/Gleichrangige. Die drei alten down-Overrides (emp/kpi/shift,
--     Schnitt-5-Artefakt) fallen weg → Rollen-Standard greift.
-- Die 4 positionslosen MA (Alban Krasniqi, Festina Vërshefci, Rrahim Jashari, Saranda Ahmeti) sind terminierte
-- Ex-MA (kein Login) → hier nicht angefasst, nur gemeldet.

begin;

create or replace function public.perm_emp_row_ok(p_uid uuid, p_area text, p_emp_id uuid, p_project text, p_skill text, p_position text)
returns boolean language plpgsql stable security definer set search_path=public as $$
declare crank int; rrank int; dir text;
begin
  if p_emp_id is not null and p_emp_id = public.perm_caller_emp_id(p_uid) then return true; end if;  -- eigene Zeile immer
  if not public.perm_proj_ok(p_uid, p_area, p_project, p_skill) then return false; end if;
  crank := public.perm_caller_rank(p_uid);
  -- Positionslose MA defensiv als hoch (verborgen) behandeln, nicht als unterste Ebene.
  rrank := case when p_position is null or p_position = '' then 999 else public.ai_position_rank(p_position) end;
  dir  := coalesce(public.perm(p_uid,p_area)->>'direction','down');
  if rrank > crank and dir <> 'up'  then return false; end if;   -- höher sehen nur bei 'up'
  if rrank = crank and dir =  'down' then return false; end if;   -- 'down' ohne gleiche Ebene
  return true;
end $$;

-- Ylli: Position korrigieren + alte Overrides entfernen (Rollen-Standard projektleiter = dir=side greift dann).
update public.employees set position='Projektleiter'
  where id = (select employee_id from public.app_users where user_id='312020fc-5857-4591-9a1c-f963700053b1');
delete from public.user_permissions where user_id='312020fc-5857-4591-9a1c-f963700053b1';

commit;

-- ── ROLLBACK (manuell) ──
-- update public.employees set position='Teamleiter' where id=(select employee_id from public.app_users where user_id='312020fc-5857-4591-9a1c-f963700053b1');
-- (Yllis Overrides waren emp/kpi/shift direction=down; bei Bedarf aus git/Schnitt-5 wiederherstellen.)
-- (perm_emp_row_ok: rrank := public.ai_position_rank(p_position);  -- ohne null-Guard)
