-- Tarife je Mandat mit Rangfolge. Aus der Rangfolge leitet das System das Ergebnis ab, der Agent wählt nur
-- „Tarif vorher" und „Tarif neu": höherer Rang = Upgrade, niedrigerer = Downgrade, gleicher Rang = gleiche
-- Tarifklasse (MN 150 → MN 300 ist Upgrade, MN 300 → MN 150 Downgrade, MN 150 → MN 150 seitwärts).
-- Start sind die vier MN-Tarife aus der Spezifikation; weitere pflegt das Management im HR-Portal ohne Code.
-- Gleicher Rang für zwei Tarife ist erlaubt und heißt bewusst „gleiche Klasse".
insert into public.app_config(key, value) values ('jsr_cpo_tariffs_v1', jsonb_build_object(
  'proj_gn_e5f6a7b8/retention', jsonb_build_array(
    jsonb_build_object('name','MN 150','rank',1),
    jsonb_build_object('name','MN 300','rank',2),
    jsonb_build_object('name','MN 600','rank',3),
    jsonb_build_object('name','MN 1000','rank',4)
  ))) on conflict (key) do nothing;

-- Der gewählte Tarif wird mitgeschrieben: sonst ließe sich später nicht prüfen, warum ein Abschluss als
-- Upgrade gezählt wurde, wenn jemand die Rangfolge ändert.
alter table public.cpo_entries add column if not exists tariff_from text;
alter table public.cpo_entries add column if not exists tariff_to   text;

-- Casenummern-Format (User 2026-09-23): CS oder IMS, gefolgt von Ziffern. So fällt ein Zahlendreher sofort auf.
-- Gespeichert wird in Großbuchstaben, damit „cs5006433" und „CS5006433" derselbe Case sind.
alter table public.cpo_entries drop constraint if exists cpo_entries_case_no_ck;
alter table public.cpo_entries add  constraint cpo_entries_case_no_ck
  check (case_no ~ '^(CS|IMS)[0-9]{4,12}$');
