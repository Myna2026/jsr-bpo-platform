-- Arlinda Sopa (Trainerin, Support) zaehlt nicht in die Abrechnung, wie Mergim und Edi.
-- Vorgabe des Eigentuemers vom 2026-09-29. Damit hat jede Overhead-Rolle im HC-Team einen
-- hinterlegten Anteil; der Hinweis "ohne hinterlegten Anteil" im Bericht verschwindet.
update public.app_config
   set value = jsonb_set(value, '{entries}',
         (value->'entries') || jsonb_build_array(
           jsonb_build_object('id','hcb_arlinda','emp','03408b6b-6cc6-4406-b43f-6587fcfd6b60',
                              'pct',0,'from',null,'to',null,'note','Trainerin, nicht in der Abrechnung')))
 where key = 'jsr_hc_billing_v1'
   and not (value->'entries') @> '[{"emp":"03408b6b-6cc6-4406-b43f-6587fcfd6b60"}]'::jsonb;

select e->>'emp' emp, (e->>'pct')::numeric pct, e->>'note' note,
       coalesce(x.first_name||' '||x.last_name,'?') name
  from public.app_config c
  cross join lateral jsonb_array_elements(c.value->'entries') e
  left join public.employees x on x.id::text = e->>'emp'
 where c.key='jsr_hc_billing_v1' order by pct, name;
