-- Aushilfen in der Retention: Leute, die Vorgaenge erfassen, deren Stunden aber ueber ihren eigenen
-- Skill abgerechnet werden (Vorgabe User 2026-10-01). Ihre Abschluesse und der CPO zaehlen zu Retention,
-- Stunden nicht: keine Stundenverguetung, kein Rueckfallwert, und KEINE Meldung ueber fehlende Stunden,
-- denn es fehlt nichts, es wird nichts erwartet.
-- Schluessel je Mandat "<projekt>/<skill>", Werte sind Mitarbeiter-IDs. Pflegbar im Leitstand.
insert into app_config (key, value)
values ('jsr_cpo_helpers_v1', jsonb_build_object('proj_gn_e5f6a7b8/retention', jsonb_build_array(
  'ffc49961-2716-4e9d-9c7e-2edac03c60ac',   -- Faton Bahtiri, Skill Doku
  'a41e7495-5be4-4d53-bccf-4ea70a760d39',   -- Enesa Palloshi
  '93faa195-0bde-447a-a7cb-8f773ba2989e'    -- Nurije Cikaqi
)))
on conflict (key) do nothing;

select value from app_config where key='jsr_cpo_helpers_v1';
