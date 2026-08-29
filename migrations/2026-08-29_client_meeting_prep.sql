-- Vorhaben 2 (Kundentermin vorbereiten), Schnitt 1: Pauls Fakten-RPC. Deterministisch, KEINE KI.
-- Liefert je Skill die kundenrelevanten Kennzahlen (Team-Schnitt letzte 6 KWs + letzter/vorheriger Wert +
-- Richtung), Forecast der letzten Wochen, Besetzung und anstehende Abwesenheiten. Nur Management/Projektleiter.
-- Team-Schnitt = einfacher Mittelwert der Agent-Werte (bewusst simpel; Pauls Synthese in Schnitt 2 ordnet ein).
create or replace function public.client_meeting_prep(p_project text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare d date := (now() at time zone 'Europe/Berlin')::date;
        cur_yw int := extract(isoyear from d)::int*100 + extract(week from d)::int;
        lo_yw int := cur_yw - 6;   -- ~6 KWs zurück (innerhalb desselben Jahres sauber; Jahreswechsel unscharf)
begin
  if not (public.is_management() or (public.is_planner() and p_project = public.get_my_employee_project_id())) then
    return jsonb_build_object('error','nicht berechtigt');
  end if;

  return jsonb_build_object(
    'project', p_project,
    'project_name', (select name from public.projects where id=p_project),
    'generated_yw', cur_yw,
    -- Kennzahlen je Skill: Reihe (KW->Team-Schnitt) + letzter/vorheriger Wert + Richtung
    'kpis', (
      select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
        select s.skill, s.kpi, s.unit,
          (select jsonb_object_agg(w.yw, w.avg_val) from (
             select ke.year*100+ke.kw as yw, round(avg(ke.value)::numeric,2) as avg_val
             from public.kpi_entries ke join public.employees e on e.id=ke.emp_id
             where e.project_id=p_project and ke.kpi_id=s.kpi_id and ke.year*100+ke.kw between lo_yw and cur_yw
             group by ke.year*100+ke.kw) w) as series,
          (select round(avg(ke.value)::numeric,2) from public.kpi_entries ke join public.employees e on e.id=ke.emp_id
             where e.project_id=p_project and ke.kpi_id=s.kpi_id and ke.year*100+ke.kw=(
               select max(ke2.year*100+ke2.kw) from public.kpi_entries ke2 join public.employees e2 on e2.id=ke2.emp_id
               where e2.project_id=p_project and ke2.kpi_id=s.kpi_id and ke2.year*100+ke2.kw<=cur_yw)) as latest,
          (select round(avg(ke.value)::numeric,2) from public.kpi_entries ke join public.employees e on e.id=ke.emp_id
             where e.project_id=p_project and ke.kpi_id=s.kpi_id and ke.year*100+ke.kw=(
               select max(ke2.year*100+ke2.kw) from public.kpi_entries ke2 join public.employees e2 on e2.id=ke2.emp_id
               where e2.project_id=p_project and ke2.kpi_id=s.kpi_id and ke2.year*100+ke2.kw<cur_yw and ke2.year*100+ke2.kw<(
                 select max(ke3.year*100+ke3.kw) from public.kpi_entries ke3 join public.employees e3 on e3.id=ke3.emp_id
                 where e3.project_id=p_project and ke3.kpi_id=s.kpi_id and ke3.year*100+ke3.kw<=cur_yw))) as prev
        from (
          select distinct kc.id as kpi_id, kc.name as kpi, lower(kc.skill) as skill, kc.unit
          from public.kpi_config kc
          where coalesce(kc.level,'agent')<>'team'
            and exists (select 1 from public.kpi_entries ke join public.employees e on e.id=ke.emp_id
                        where e.project_id=p_project and ke.kpi_id=kc.id)
        ) s order by s.skill, s.kpi
      ) x
    ),
    -- Forecast letzte Wochen je Skill (Bedarf) + Ist-Stunden falls vorhanden
    'forecast', (
      select coalesce(jsonb_agg(jsonb_build_object('skill',rf.skill,'yw',rf.year*100+rf.kw,'fc_hours',round(rf.fc_hours::numeric,1)) order by rf.skill, rf.year*100+rf.kw), '[]'::jsonb)
      from public.report_forecast rf where rf.project_id=p_project and rf.year*100+rf.kw between lo_yw and cur_yw and rf.fc_hours>0
    ),
    -- Call-Qualität: Team-AHT (gewichtet nach answered) + answered je letzter Wochen
    'calls', (
      select coalesce(jsonb_agg(row_to_json(c)), '[]'::jsonb) from (
        select wc.year*100+wc.kw as yw, sum(wc.answered) as answered,
          round((sum(wc.avg_handle_sec*wc.answered)/nullif(sum(wc.answered),0))::numeric,0) as aht_sec
        from public.weekly_calls wc where wc.project_id=p_project and wc.year*100+wc.kw between lo_yw and cur_yw
        group by wc.year*100+wc.kw order by wc.year*100+wc.kw) c
    ),
    -- Besetzung je Skill (aktiv)
    'staffing', (
      select coalesce(jsonb_object_agg(sk, n), '{}'::jsonb) from (
        select lower(project_skill) as sk, count(*) as n from public.employees
        where project_id=p_project and status in ('active','training') and project_skill is not null group by lower(project_skill)) q
    ),
    -- anstehende Abwesenheiten (nächste 14 Tage)
    'absences_soon', (
      select coalesce(jsonb_agg(jsonb_build_object('name', e.first_name||' '||e.last_name, 'skill', lower(e.project_skill),
               'type', a->>'type', 'from', a->>'from', 'to', coalesce(nullif(a->>'to',''), a->>'from')) ), '[]'::jsonb)
      from public.employees e, jsonb_array_elements(coalesce(e.absences,'[]'::jsonb)) a
      where e.project_id=p_project and (a->>'from') ~ '^\d{4}-\d{2}-\d{2}'
        and (a->>'from')::date <= d+14 and coalesce(nullif(a->>'to',''),(a->>'from'))::date >= d
    )
  );
end $$;
grant execute on function public.client_meeting_prep(text) to authenticated;
