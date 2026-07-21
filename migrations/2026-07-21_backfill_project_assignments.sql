-- =============================================================================
-- Backfill project_assignments + Skill-Korrektur (Giganetz-Import)     2026-07-21
-- =============================================================================
-- Zweck (in einem Rutsch):
--   A) Skill-Korrektur am flachen employees.project_skill für die Giganetz-
--      Importe: die falschen Import-Skills outbound/inbound → die echten
--      Projekt-Keys retention / 1st_level.
--   B) Backfill der project_assignments (jsonb-Spalte an employees) für die
--      importierten MA, abgeleitet aus dem flachen project_id / project_skill
--      (nach Korrektur) / hire_date. Ein offener Eintrag (end_date=null).
--
-- Reihenfolge zwingend: A vor B (der Backfill liest das korrigierte project_skill).
-- Nicht-destruktiv: das flache project_id/project_skill bleibt erhalten
--   (alle bestehenden Filter, die e.project_id lesen, laufen unverändert weiter).
-- Idempotent: A trifft nur noch-falsche Werte, B nur MA ohne Zuweisung.
--
-- NICHT ausführen ohne Kontrolle. Erst §0 (Vorschau) laufen lassen, die echten
-- Skill-Keys prüfen und ggf. die zwei Zielstrings in §1 anpassen. Dann §1–§3.
--
-- WICHTIG — Skill-Keys verifizieren: Die echten Giganetz-Keys stehen in
-- public.project_skills. Sollten sie anders lauten als 'retention' / '1st_level'
-- (z.B. 'first_level'), die beiden Zielwerte in §1 entsprechend ändern.
-- =============================================================================

-- Projekt-IDs (text): Giganetz = proj_gn_e5f6a7b8, Holidaycheck = proj_hc_a1b2c3d4


-- -----------------------------------------------------------------------------
-- §0 VORSCHAU — erst laufen, NICHTS wird geändert. Zeigt echte Keys + Wirkung.
-- -----------------------------------------------------------------------------
-- (a) Echte Skill-Keys der Projekte (Zielwerte für §1 hier ablesen/bestätigen):
select project_id, key, label
from public.project_skills
where project_id in ('proj_gn_e5f6a7b8','proj_hc_a1b2c3d4')
order by project_id, key;

-- (b) Aktuelle flache Skills der importierten MA je Projekt (zeigt outbound/inbound
--     bei Giganetz und support/sales/all bei HC — 'all' ist nur ein neutraler
--     Platzhalter, kein echter HC-Skill, wird NICHT korrigiert):
select project_id, coalesce(nullif(project_skill,''),'(kein Skill)') as project_skill, count(*)
from public.employees
where import_source is not null and nullif(project_id,'') is not null
group by project_id, project_skill
order by project_id, count(*) desc;

-- (c) Was der Backfill anlegen würde (MA mit project_id, noch ohne Zuweisung):
select project_id, count(*) as bekommt_zuweisung
from public.employees
where import_source is not null
  and nullif(project_id,'') is not null
  and jsonb_array_length(coalesce(project_assignments,'[]'::jsonb)) = 0
group by project_id order by bekommt_zuweisung desc;

-- (d) MA ohne project_id — bekommen KEINE Zuweisung (bleiben unassigned):
select count(*) as ohne_projekt
from public.employees
where import_source is not null and nullif(project_id,'') is null;


-- -----------------------------------------------------------------------------
-- §1 SKILL-KORREKTUR — nur Giganetz-Importe, nur die falschen Werte.
--    (Zielstrings ggf. an §0(a) anpassen.)
-- -----------------------------------------------------------------------------
update public.employees
set project_skill = case lower(project_skill)
                      when 'outbound' then 'retention'
                      when 'inbound'  then '1st_level'
                      else project_skill
                    end
where import_source is not null
  and project_id = 'proj_gn_e5f6a7b8'
  and lower(coalesce(project_skill,'')) in ('outbound','inbound');


-- -----------------------------------------------------------------------------
-- §2 BACKFILL project_assignments — ein offener Eintrag pro importiertem MA
--    mit project_id, abgeleitet aus den (jetzt korrigierten) flachen Feldern.
-- -----------------------------------------------------------------------------
update public.employees e
set project_assignments = jsonb_build_array(
      jsonb_build_object(
        'employee_id', e.id,
        'project_id',  e.project_id,
        'skill',       nullif(e.project_skill, ''),   -- leer → null
        'start_date',  e.hire_date,                   -- date → "YYYY-MM-DD" (null erlaubt)
        'end_date',    null                           -- offen = aktuell laufend
      )
    )
where e.import_source is not null
  and nullif(e.project_id, '') is not null
  and jsonb_array_length(coalesce(e.project_assignments, '[]'::jsonb)) = 0;  -- nur unbelegte → idempotent


-- -----------------------------------------------------------------------------
-- §3 KONTROLLE — sollte 0 offene Kandidaten und keine outbound/inbound mehr zeigen.
-- -----------------------------------------------------------------------------
select
  (select count(*) from public.employees
     where import_source is not null and nullif(project_id,'') is not null
       and jsonb_array_length(coalesce(project_assignments,'[]'::jsonb)) = 0)          as backfill_offen,
  (select count(*) from public.employees
     where import_source is not null and project_id='proj_gn_e5f6a7b8'
       and lower(coalesce(project_skill,'')) in ('outbound','inbound'))               as skill_unkorrigiert;
