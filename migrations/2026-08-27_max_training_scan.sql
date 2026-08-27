-- Max überwacht die Schulung — der kritischste Punkt im Recruiting. Zwei Prüfungen, nähe-gestaffelt:
--  1) Soll gegen Ist + Countdown: geplante Plätze (planned_count) vs zugeordnete Teilnehmer
--     (confirmed_ids). Dringlichkeit nach Nähe zum Start:
--       <=3 Tage  -> schulung_kritisch (Problem)
--       <=14 Tage -> schulung_knapp   (wird eng)
--       >14 Tage  -> schulung_offen   (Hinweis)
--  2) schulung_abgesprungen: ein zugeordneter Teilnehmer hat vor Start gekündigt/abgesprungen/Blacklist.
-- Nur anstehende, noch nicht produktive Gruppen (start_date >= heute, active_date offen/zukünftig).
-- p_date = Bezugstag (Default heute, Berlin). Service-role only.
create or replace function public.max_training_scan(p_date date default null)
returns table(category text, subject text, detail text)
language plpgsql stable security definer set search_path=public as $$
declare d date := coalesce(p_date, (now() at time zone 'Europe/Berlin')::date);
begin
  return query
  with plans as (
    select tp.id,
      coalesce(nullif(tp.name,''),'Schulung') as nm,
      coalesce((select p.name from public.projects p where p.id=tp.project_id),'?') as proj,
      tp.start_date,
      coalesce(tp.planned_count,0) as soll,
      coalesce(jsonb_array_length(tp.confirmed_ids),0) as ist,
      (tp.start_date - d) as dleft,
      tp.confirmed_ids
    from public.training_plans tp
    where tp.start_date is not null and tp.start_date >= d
      and (tp.active_date is null or tp.active_date > d)
      and coalesce(lower(tp.status),'') not in ('cancelled','abgesagt','storniert','done','fertig','abgeschlossen')
  )
  -- 1) unterbesetzt + Countdown (je näher der Start, desto dringlicher)
  select
    (case when pl.dleft<=3 then 'schulung_kritisch' when pl.dleft<=14 then 'schulung_knapp' else 'schulung_offen' end)::text,
    pl.nm||' · '||pl.proj,
    'startet '||(case when pl.dleft<=0 then 'heute' when pl.dleft=1 then 'morgen' else 'in '||pl.dleft||' Tagen' end)
      ||' ('||to_char(pl.start_date,'DD.MM.')||'), geplant '||pl.soll||' Plätze, zugeordnet '||pl.ist
      ||' — es fehlen noch '||(pl.soll-pl.ist)||'. '
      ||(case when pl.dleft<=3  then 'So kurz vor Start ist das kritisch: die Gruppe geht zu klein an den Start und der Bedarf bleibt ungedeckt.'
              when pl.dleft<=14 then 'Es rückt näher und wird eng — jetzt nachbesetzen, sonst startet die Gruppe unterbesetzt.'
              else 'Noch etwas Zeit, aber die Plätze sollten sich füllen.' end)
    from plans pl
    where pl.soll > 0 and pl.ist < pl.soll
  union all
  -- 2) zugeordneter Teilnehmer vor Start abgesprungen/gekündigt
  select 'schulung_abgesprungen'::text, pl.nm||' · '||pl.proj,
    (e.first_name||' '||e.last_name)||' war der Gruppe zugeordnet, ist aber '||
      (case when e.status like 'terminated%' then 'gekündigt'
            when e.status like 'rejected%'   then 'abgesprungen (abgelehnt oder zurückgezogen)'
            when e.status='blacklist'        then 'auf die Blacklist gesetzt'
            else 'nicht mehr im Prozess' end)
      ||' — die Gruppe schrumpft schon vor Start ('||to_char(pl.start_date,'DD.MM.')||'), es braucht Nachbesetzung'
    from plans pl
    cross join lateral jsonb_array_elements_text(coalesce(pl.confirmed_ids,'[]'::jsonb)) cid
    join public.employees e on e.id::text = cid
    where e.status like 'terminated%' or e.status like 'rejected%' or e.status='blacklist';
end $$;
grant execute on function public.max_training_scan(date) to service_role;
