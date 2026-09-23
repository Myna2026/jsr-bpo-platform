-- Kundenportal rechnete Durchschnitte als einfachen Mittelwert über Agenten und Wochen. Bei unterschiedlich
-- vielen Gesprächen ist das falsch: gerechnet werden muss über Zähler und Nenner. Dafür braucht die Kundensicht
-- die Gewichte, die im Portal schon vorliegen (kpi_entries.raw, weekly_calls.answered, weekly_gauges.anzahl).
--   weight    = Nenner der Kennzahl (CSAT: Bewertungen · AHT/ACW: angenommene Anrufe · Mails/h: Stunden · CR: Sales Calls)
--   numerator = Zähler, wo er direkt vorliegt (Mails/h: Mails · CR: Offene+OSL), SCHON so skaliert, dass
--               Σ numerator ÷ Σ weight direkt in der Einheit der Kennzahl herauskommt (Quote ×100, Rate ×1).
-- Beides NUR für Kennzahlen, bei denen ein Durchschnitt überhaupt gewichtet gehört. Mengen (Buchungen, Sales
-- Calls) werden summiert und bekommen kein Gewicht. QM bekommt keines: die Zahl der bewerteten Gespräche steht
-- nirgends, „Answered" wäre ein erfundenes Gewicht. Ohne Gewicht bleibt der Mittelwert, sichtbar gekennzeichnet.
create or replace view public.kpi_entries_client_view as
 select e.kpi_id,
    e.kw,
    e.year,
    e.value,
    case
      when lower(c.name) = 'csat'   then coalesce(nullif(e.raw->>'anzahl','')::numeric, wg.anzahl::numeric)
      when c.unit = 'min'           then coalesce(nullif(e.raw->>'answered','')::numeric, wc.answered::numeric)
      when lower(c.name) = 'mails/h' then nullif(e.raw->>'hours','')::numeric
      when lower(c.name) = 'cr'      then nullif(e.raw->>'sales_calls','')::numeric
      else null::numeric
    end as weight,
    case
      when lower(c.name) = 'mails/h' then nullif(e.raw->>'mails','')::numeric
      when lower(c.name) = 'cr'      then (coalesce(nullif(e.raw->>'open','')::numeric,0) + coalesce(nullif(e.raw->>'osl','')::numeric,0)) * 100
      else null::numeric
    end as numerator
   from kpi_entries e
     join kpi_config c on c.id = e.kpi_id
     left join weekly_calls  wc on wc.employee_id  = e.emp_id and wc.kw = e.kw and wc.year = e.year
     left join weekly_gauges wg on wg.employee_id  = e.emp_id and wg.kw = e.kw and wg.year = e.year
  where c.project_id = get_my_client_project_id();
-- create or replace view setzt die reloptions zurueck -> Haertung wiederherstellen (wie die anderen Kundensichten).
alter view public.kpi_entries_client_view set (security_invoker = false, security_barrier = true);
