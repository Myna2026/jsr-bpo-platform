-- Giganetz Retention: Tarif MN 400 aufnehmen, Rangfolge neu durchnummerieren.
--
-- MN 400 gibt es nicht mehr im Verkauf, Bestandskunden haben ihn noch ("legacy").
-- Er ist als "Tarif vorher" waehlbar, als "Tarif neu" nur beim Halten (dann seitwaerts).
-- Rang zwischen MN 300 und MN 600, deshalb die glatte Neunummerierung 1..5 statt Zwischenwerten.
-- Schon erfasste Vorgaenge behalten ihr Ergebnis: es ist beim Erfassen eingefroren.
update public.app_config
   set value = jsonb_set(value, '{proj_gn_e5f6a7b8/retention}', jsonb_build_array(
         jsonb_build_object('name','MN 150' ,'rank',1),
         jsonb_build_object('name','MN 300' ,'rank',2),
         jsonb_build_object('name','MN 400' ,'rank',3,'legacy',true),
         jsonb_build_object('name','MN 600' ,'rank',4),
         jsonb_build_object('name','MN 1000','rank',5)
       ))
 where key = 'jsr_cpo_tariffs_v1';

select jsonb_pretty(value->'proj_gn_e5f6a7b8/retention') tarife
  from public.app_config where key='jsr_cpo_tariffs_v1';
