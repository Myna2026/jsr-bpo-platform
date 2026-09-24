-- Protokoll (activity_log): Lesepolicy für Leads von 8 Sekunden Abbruch auf Millisekunden.
--
-- Befund 2026-09-24 (Zugang Arsyela Delishaj, Projektleiterin Condor): jede Leseabfrage auf activity_log
-- brach mit 57014 ab (Zeitüberschreitung nach ~8 s). Management war mit 431 ms unauffällig.
-- Ursache: die Policy `activity_read` bestimmte JE ZEILE über eine korrelierte Unterabfrage
-- (app_users join employees) das Projekt des Handelnden und rief damit `perm_proj_ok` — bei 12.010 Zeilen
-- also 12.010 mal eine Funktion, die selbst mehrere Abfragen macht. Für Management griff der
-- Kurzschluss „alle Projekte", für Projektleiter und Teamleads nicht. Betraf Ylli und Edi genauso.
--
-- Neu: die Menge der sichtbaren Handelnden wird EINMAL je Abfrage bestimmt (Skalar-Unterabfrage =
-- InitPlan), danach ist es ein Indexzugriff über idx_activity_log_user_time (user_id, created_at DESC).
-- Die Sichtbarkeit bleibt Zeile für Zeile dieselbe:
--   * perm_allowed_projects = NULL (alle Projekte)      -> alles sichtbar, wie vorher
--   * sonst                                             -> nur Handelnde, deren Mitarbeiter-Datensatz in
--                                                          einem erlaubten Projekt liegt
--   * Handelnde ohne Mitarbeiter-Datensatz (z. B. reine Systemzugänge) bleiben für Leads unsichtbar,
--     genau wie vorher (perm_proj_ok lieferte bei NULL-Projekt false).
-- Die Skill-Achse ist für den Bereich 'protokoll' aus (perm_area_has_skill('protokoll') = false), der
-- alte Aufruf übergab ohnehin NULL — die Vereinfachung ändert die Logik nicht.
--
-- Rückbau:
--   drop policy activity_read on public.activity_log;
--   create policy activity_read on public.activity_log for select using (
--     (perm_mode(auth.uid(),'protokoll') <> 'none') and perm_proj_ok(auth.uid(),'protokoll',
--       (select e.project_id from app_users au join employees e on e.id=au.employee_id
--         where au.user_id = activity_log.user_id limit 1), null));

-- Wessen Handlungen darf dieser Nutzer im Protokoll sehen? NULL = alle (keine Einschränkung).
-- SECURITY DEFINER, weil die Auflösung über app_users/employees sonst in deren eigene RLS liefe.
create or replace function public.protokoll_visible_users(p_uid uuid)
returns uuid[]
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare allowed text[]; ids uuid[];
begin
  allowed := public.perm_allowed_projects(p_uid, 'protokoll');
  if allowed is null then return null; end if;                 -- alle Projekte, keine Einschränkung
  select coalesce(array_agg(au.user_id), '{}'::uuid[]) into ids
    from public.app_users au
    join public.employees e on e.id = au.employee_id
   where e.project_id = any(allowed);
  return ids;
end $function$;

grant execute on function public.protokoll_visible_users(uuid) to authenticated;

drop policy if exists activity_read on public.activity_log;

create policy activity_read on public.activity_log
  for select
  using (
    (select public.perm_mode(auth.uid(), 'protokoll')) <> 'none'
    and (
      (select public.protokoll_visible_users(auth.uid())) is null
      -- coalesce(...) statt blankem Unterausdruck: `= any (<Unterabfrage>)` liest Postgres als
      -- Zeilenmenge und vergleicht uuid mit uuid[] (42883). So bleibt es ein Array-Ausdruck.
      or user_id = any (coalesce((select public.protokoll_visible_users(auth.uid())), '{}'::uuid[]))
    )
  );
