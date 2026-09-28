-- Abrechenbare Anteile HolidayCheck (Vorgabe des Eigentuemers vom 2026-09-28).
-- Ohne Eintrag zaehlt eine Person voll. Die Anteile sind im Leitstand unter
-- "HC Stundenabgleich → Abrechenbare Anteile" ohne Code aenderbar.
--   Mergim Gecaj     0 %   gar nicht abrechnen
--   Bleart Leci     50 %
--   Ardita Hysenaj  75 %
--   Albanitë Hetemi 100 %, aber 0 % solange eine HC-Schulung laeuft (training_zero)
--   Edi Shaqiri      0 %   Projektleiter, protokolliert keine Stunden (nachgetragen 2026-09-28)
insert into public.app_config (key, value) values (
  'jsr_hc_billing_v1',
  jsonb_build_object(
    'default_pct', 100,
    'entries', jsonb_build_array(
      jsonb_build_object('id','hcb_mergim','emp','1ab9623d-b9b2-475d-92ae-aaeffdae1ae5','pct',0 ,'from',null,'to',null,'note','gar nicht abrechnen'),
      jsonb_build_object('id','hcb_bleart','emp','62603706-5005-4b17-a524-8b19e9b8cf93','pct',50,'from',null,'to',null,'note',null),
      jsonb_build_object('id','hcb_ardita','emp','1c5f549e-4e60-43a7-98b0-fd3041c7f1a2','pct',75,'from',null,'to',null,'note',null),
      jsonb_build_object('id','hcb_albanite','emp','b95caa01-f45d-40fc-880a-b99e4b091693','pct',100,'from',null,'to',null,'note','0 % waehrend einer Schulungsklasse'),
      jsonb_build_object('id','hcb_edi','emp','bec69adc-6ed2-4b41-bf43-7a120a33e824','pct',0 ,'from',null,'to',null,'note','Projektleiter, nicht in der Abrechnung')
    ),
    'training_zero', jsonb_build_array('b95caa01-f45d-40fc-880a-b99e4b091693')
  )
)
on conflict (key) do update set value = excluded.value;

select key, jsonb_array_length(value->'entries') regeln, value->'training_zero' schulung_null
  from public.app_config where key='jsr_hc_billing_v1';
