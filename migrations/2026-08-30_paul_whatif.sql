-- "Was wäre wenn" (Paul), Schnitt 1: die RECHNUNG. Je Projekt+Skill, nie über Skill-Grenzen.
-- Verteilung (bestes/schwächstes Drittel), Szenarien (Schnitt → Median / → bestes Drittel), der Hebel
-- (um wie viel muss das schwächste Drittel steigen) und die konkrete Größe (bei %-KPIs über das Volumen).
-- Grundlage mind. 4 Wochen (Momentaufnahme-Schutz: eine Woche macht niemanden schwach), Wochenzahl sichtbar.
-- Drilldown mit Namen NUR für die Berechtigten (Gate = wie Personal-Vorschau: Management ODER Projektleiter des
-- eigenen Projekts; KEIN Teamleiter, KEIN HR). KEINE Empfehlung über Personen (das wäre ein Urteil, Leitplanke).
-- sick fließt NICHT ein (kein Hebel). Läuft NICHT über agent_insights → keine Einblendung, nur abrufbar.
create or replace function public.paul_whatif(p_project text, p_min_weeks int default 4, p_min_people int default 6)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_pname text; v_skills jsonb := '[]'::jsonb; v_block jsonb;
  r_skill record; v_kpi_id text; v_kpi_name text; v_unit text; v_higher boolean; v_nweeks int;
begin
  -- Gate: Management (alle Projekte) ODER Projektleiter des eigenen Projekts. Bewusst NICHT is_planner()
  -- (das schlösse Teamleiter ein). Wie die Personal-Vorschau, aber eng.
  if not ( public.is_management()
    or ( exists(select 1 from public.app_users au where au.user_id=auth.uid() and au.active
                and au.role_keys && array['projektleiter']::text[])
         and p_project = public.get_my_employee_project_id() ) ) then
    raise exception 'Nur Management oder der Projektleiter dieses Projekts.';
  end if;

  select name into v_pname from public.projects where id=p_project;
  if v_pname is null then return jsonb_build_object('error','Projekt nicht gefunden'); end if;

  for r_skill in
    select distinct skill from public.kpi_config
    where project_id=p_project and level='agent' and skill is not null and skill<>'' loop

    -- KPI-Wahl: is_primary → CR (Conversion) → beste Abdeckung. Richtung: Minuten = kleiner besser, sonst größer besser.
    select c.id, c.name, c.unit, (lower(coalesce(c.unit,'')) not like '%min%')
      into v_kpi_id, v_kpi_name, v_unit, v_higher
      from public.kpi_config c
      left join (select kpi_id, count(*) n from public.kpi_entries group by kpi_id) e on e.kpi_id=c.id
     where c.project_id=p_project and c.level='agent' and c.skill=r_skill.skill
     order by c.is_primary desc nulls last, (lower(c.name)='cr') desc, coalesce(e.n,0) desc
     limit 1;
    if v_kpi_id is null then continue; end if;

    with wk as (   -- die jüngsten bis zu 8 Wochen mit Daten für diesen KPI (Grundlage)
      select year,kw from public.kpi_entries where kpi_id=v_kpi_id group by year,kw order by year desc,kw desc limit 8
    ),
    per as (       -- je Mitarbeiter der Schnitt über das Fenster (nicht eine einzelne Woche)
      select e.emp_id, round(avg(e.value)::numeric,2) val, count(distinct e.kw) wc
      from public.kpi_entries e join wk using(year,kw)
      where e.kpi_id=v_kpi_id group by e.emp_id
    ),
    rk as (        -- Drittel: bestes zuerst (Richtung beachtet)
      select per.*, ntile(3) over (order by per.val * (case when v_higher then -1 else 1 end)) tile from per
    ),
    agg as (
      select count(*) n,
             round(avg(val),2) cur,
             round((percentile_cont(0.5) within group (order by val))::numeric,2) med,
             round(avg(val) filter (where tile=1),2) benchmark,
             round(avg(val) filter (where tile=3),2) bottom
      from rk
    ),
    scen as (
      select
        round((select avg(case when (v_higher and val>=(select benchmark from agg)) or (not v_higher and val<=(select benchmark from agg)) then val else (select benchmark from agg) end) from rk),2) new_bench,
        round((select avg(case when (v_higher and val>=(select med from agg))       or (not v_higher and val<=(select med from agg))       then val else (select med from agg)       end) from rk),2) new_med
    ),
    vol as (       -- Volumen je Woche für die konkrete Übersetzung (Sales-Calls des Skills)
      select coalesce(sum(wh.sales_calls),0)::numeric v, greatest(count(distinct (wh.year::text||'-'||wh.kw::text)),1) w
      from public.weekly_hours wh join wk using(year,kw)
      where wh.project_id=p_project and wh.skill=r_skill.skill
    )
    select jsonb_build_object(
      'skill', r_skill.skill,
      'kpi', v_kpi_name, 'unit', v_unit, 'higher_is_better', v_higher,
      'n_people', a.n,
      'weeks', jsonb_build_object('n',(select count(*) from wk),'von_kw',(select min(kw) from wk),'bis_kw',(select max(kw) from wk)),
      'current_avg', a.cur, 'median', a.med, 'benchmark', a.benchmark, 'bottom_third', a.bottom,
      'gap_top_bottom', round(abs(a.benchmark - a.bottom),2),
      'scenario_to_median',    jsonb_build_object('new_avg', s.new_med,   'delta', round(s.new_med  - a.cur,2)),
      'scenario_to_benchmark', jsonb_build_object('new_avg', s.new_bench, 'delta', round(s.new_bench - a.cur,2),
        'konkret', case when lower(coalesce(v_unit,''))='%' and (select v from vol)>0
          then jsonb_build_object('einheit','Abschlüsse/Woche',
                 'volumen_woche', round((select v from vol)/(select w from vol),0),
                 'delta_pro_woche', round((s.new_bench - a.cur)/100.0 * ((select v from vol)/(select w from vol)),1))
          else null end),
      'hebel', jsonb_build_object('schwaechstes_drittel_heben_um', round(abs(a.benchmark - a.bottom),2),
               'einheit', coalesce(v_unit,'')),
      'machbarkeit', jsonb_build_array(
        'Leistung heben braucht Zeit (Coaching, Einarbeitung), nicht kurzfristig.',
        'Kundenprojekt: Besetzungs- oder Volumenänderungen brauchen Abstimmung mit dem Kunden.'),
      'people', (select jsonb_agg(jsonb_build_object(
                    'name', nullif(btrim(coalesce(em.first_name,'')||' '||coalesce(em.last_name,'')),''),
                    'value', rk.val,
                    'gruppe', case rk.tile when 1 then 'stark' when 2 then 'mittel' else 'schwach' end,
                    'weeks', rk.wc)
                  order by rk.val * (case when v_higher then -1 else 1 end))
                 from rk join public.employees em on em.id=rk.emp_id),
      'genug_daten', (a.n>=p_min_people and (select count(*) from wk)>=p_min_weeks),
      'hinweis', case when (a.n>=p_min_people and (select count(*) from wk)>=p_min_weeks) then null
                      else 'Zu dünn für eine belastbare Aussage (mind. '||p_min_people||' Personen und '||p_min_weeks||' Wochen).' end
    )
    into v_block from agg a cross join scen s;

    if v_block is not null then v_skills := v_skills || v_block; end if;
  end loop;

  return jsonb_build_object('project_id',p_project,'project_name',v_pname,
    'grundlage','Schnitt über die letzten Wochen (Momentaufnahme, nicht eine einzelne Woche).',
    'skills',v_skills);
end $$;

revoke all on function public.paul_whatif(text,int,int) from public;
grant execute on function public.paul_whatif(text,int,int) to authenticated;
