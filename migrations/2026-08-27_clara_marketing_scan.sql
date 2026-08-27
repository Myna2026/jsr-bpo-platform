-- Clara überwacht das Recruiting-Marketing (ergänzt den Ausbleib-Wächter aus agent-observe). Vier Typen:
--  1) qualitaet : Wie viele TOP/GUT kommen (letzte Woche vs Vorwoche) — der WERTVOLLSTE Punkt
--  2) kampagne  : Klickpreis/Menge je Kampagne deutlich verändert (besser/schlechter, mit Richtung)
--  3) daten_fehlt: Kampagne verschwunden (Vorwoche da, jetzt weg) oder Windsor liefert nichts mehr
-- Qualität nach der Kanban-Regel (C1&Erfahrung=TOP; C1 oder B2&Erfahrung=GUT). Service-role only.
create or replace function public.clara_marketing_scan()
returns table(category text, subject text, detail text)
language plpgsql stable security definer set search_path=public as $$
declare
  d date := (now() at time zone 'Europe/Berlin')::date;
  cur_mon  date := date_trunc('week', d)::date - 7;    -- Montag letzte (abgeschlossene) Woche
  prev_mon date := date_trunc('week', d)::date - 14;
begin
  return query
  -- 1) Qualität: TOP/GUT letzte Woche vs Vorwoche
  with q as (
    select
      case when created_at::date >= cur_mon  and created_at::date < cur_mon+7  then 'cur'
           when created_at::date >= prev_mon and created_at::date < prev_mon+7 then 'prev' end as wk,
      (case when upper(coalesce(nullif(language_level,''), extra->>'german','')) ~ 'C1|C2|MUTTERSPRACH' then 'C1'
            when upper(coalesce(nullif(language_level,''), extra->>'german','')) ~ 'B2' then 'B2' else '' end) as lang,
      (case when lower(coalesce(extra->>'cc_experience','')) ~ '^(nein|no|kein|nicht)' then false
            when lower(coalesce(extra->>'cc_experience','')) ~ '(ja|yes|jo|jahr|erfahr|agent|service|call|verkauf|[0-9])' then true end) as exp
    from public.cvs where created_at::date >= prev_mon and created_at::date < cur_mon+7
  ),
  qc as (
    select wk,
      count(*) filter (where lang='C1' and exp is true) as top,
      count(*) filter (where not (lang='C1' and exp is true) and (lang='C1' or (lang='B2' and exp is true))) as gut,
      count(*) as total
    from q where wk is not null group by wk
  ),
  qq as (
    select coalesce((select top from qc where wk='cur'),0) tc, coalesce((select gut from qc where wk='cur'),0) gc, coalesce((select total from qc where wk='cur'),0) nc,
           coalesce((select top from qc where wk='prev'),0) tp, coalesce((select gut from qc where wk='prev'),0) gp, coalesce((select total from qc where wk='prev'),0) np
  )
  select 'qualitaet'::text, 'Zulauf-Qualität letzte Woche',
    'diese Woche '||tc||' TOP / '||gc||' GUT von '||nc||', Vorwoche '||tp||' / '||gp||' von '||np||' — '||
    (case when (tc+gc) > (tp+gp) then 'die Qualität steigt, mehr taugliche Bewerbungen'
          when (tc+gc) < (tp+gp) then 'die Qualität fällt: viele billige Bewerbungen sind nichts wert, wenn keine davon taugt'
          else 'die Qualität bleibt gleich' end)
    from qq
  union all
  -- 2) Kampagne: Klickpreis (Spend/Klicks) deutlich verändert (>25%, beide Wochen mit Daten)
  select 'kampagne', c.campaign,
    'Klickpreis von €'||to_char(c.cpc_prev,'FM990.00')||' auf €'||to_char(c.cpc_cur,'FM990.00')||' ('
      ||(case when c.cpc_cur>c.cpc_prev then '+' else '' end)||round((c.cpc_cur-c.cpc_prev)/c.cpc_prev*100)||'%) — '
      ||(case when c.cpc_cur>c.cpc_prev then 'teurer, gleiche Menge kostet mehr' else 'günstiger, mehr fürs Geld' end)
    from (
      select campaign,
        sum(spend) filter (where date>=cur_mon  and date<cur_mon+7)  / nullif(sum(clicks) filter (where date>=cur_mon  and date<cur_mon+7),0)  as cpc_cur,
        sum(spend) filter (where date>=prev_mon and date<prev_mon+7) / nullif(sum(clicks) filter (where date>=prev_mon and date<prev_mon+7),0) as cpc_prev
      from public.windsor_marketing where campaign is not null and campaign<>'' group by campaign
    ) c
    where c.cpc_cur is not null and c.cpc_prev is not null and c.cpc_prev>0 and abs(c.cpc_cur-c.cpc_prev)/c.cpc_prev > 0.25
  union all
  -- 3) daten_fehlt: Kampagne lief Vorwoche mit Spend, jetzt Woche ohne jede Zeile
  select 'daten_fehlt', c.campaign,
    'lief in der Vorwoche (€'||to_char(c.sp_prev,'FM990.00')||' Spend), diese Woche keine Daten mehr — Windsor liefert für sie nichts, die Wirkung ist blind'
    from (
      select campaign,
        sum(spend) filter (where date>=prev_mon and date<prev_mon+7) as sp_prev,
        count(*)   filter (where date>=cur_mon  and date<cur_mon+7)  as rows_cur
      from public.windsor_marketing where campaign is not null and campaign<>'' group by campaign
    ) c
    where coalesce(c.sp_prev,0) > 0 and coalesce(c.rows_cur,0) = 0;
end $$;
grant execute on function public.clara_marketing_scan() to service_role;
