-- Der Mailer-Import hatte einen eigenen Alias-Speicher (app_config.jsr_mailer_alias_v1), alle anderen
-- Importe nutzen import_aliases. Dieselbe Entscheidung an zwei Orten laeuft auseinander, deshalb wird
-- der Mailer-Speicher hier einmalig uebernommen und danach geloescht. Die beiden Eintraege sind
-- bereits in import_aliases vorhanden, dieser Lauf ergaenzt nur, was fehlt.
insert into import_aliases (project_id, alias_name, employee_id, created_by_name)
select 'proj_hc_a1b2c3d4', x.key, (x.value #>> '{}')::uuid, 'Uebernahme aus jsr_mailer_alias_v1'
from app_config c, jsonb_each(c.value) x
where c.key='jsr_mailer_alias_v1' and x.value #>> '{}' <> 'skip'
  and not exists (
    select 1 from import_aliases a
    where a.project_id='proj_hc_a1b2c3d4'
      and lower(trim(a.alias_name)) = lower(trim(x.key)));

select a.alias_name, coalesce(trim(e.first_name)||' '||e.last_name,'IGNORIEREN') ziel, a.created_by_name
from import_aliases a left join employees e on e.id=a.employee_id
where a.project_id='proj_hc_a1b2c3d4' order by a.alias_name;

-- Alten Speicher entfernen, damit es nur noch eine Wahrheit gibt. Inhalt ist nachweislich in
-- import_aliases enthalten (beide Eintraege lagen dort schon).
delete from app_config where key='jsr_mailer_alias_v1';
