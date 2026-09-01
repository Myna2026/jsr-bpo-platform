-- Sales-Akquise Ausbau, Schnitt A: Datenmodell für Stufen + Bewertung. Fundament für B (Textbausteine je Stufe),
-- C (Priorisierung), D (Nachfass-Strecke). Fit-Modell als ANPASSBARE Konfiguration (app_config), nicht im Code.

-- Vorlagen je Stufe + mehrere Varianten je Stufe (Rotation beim Versand).
alter table public.sales_templates add column if not exists stage text;     -- erstansprache|nachfass1|nachfass2|letzter|reaktivierung
alter table public.sales_templates add column if not exists variant int not null default 1;

-- Leads: aktuelle Stufe + Bewertung + Firmengröße + Wachstums-/Saison-Signal.
alter table public.sales_leads add column if not exists stage text not null default 'erstansprache';
alter table public.sales_leads add column if not exists score numeric;         -- Priorität (berechnet in Schnitt C)
alter table public.sales_leads add column if not exists company_size int;       -- Mitarbeiterzahl (Apollo-Anreicherung)
alter table public.sales_leads add column if not exists growth text;            -- Signal: wächst / saisonale Spitze
create index if not exists sales_leads_stage_idx on public.sales_leads(stage);
create index if not exists sales_leads_score_idx on public.sales_leads(score desc nulls last);

-- Fit-Modell (Default aus User-Vorgabe 2026-08-31), in der Oberfläche (Schnitt C) anpassbar:
-- Branchen mit hohem Kundenkontaktvolumen; Größe = Mittelstand mit eigenem Kundenservice ohne Auslagerung
-- (Konzerne zu groß, Kleinstfirmen zu klein); Wachstum/saisonale Spitzen = Bonus.
insert into public.app_config(key,value) values ('jsr_sales_fit_v1', jsonb_build_object(
  'industries', jsonb_build_array(
    jsonb_build_object('name','Reise & Tourismus','weight',10),
    jsonb_build_object('name','Handel & E-Commerce','weight',9),
    jsonb_build_object('name','Abonnements & Subscriptions','weight',9),
    jsonb_build_object('name','Versicherung','weight',8),
    jsonb_build_object('name','Telekommunikation','weight',8),
    jsonb_build_object('name','Energieversorger','weight',8)
  ),
  'size', jsonb_build_object('min',50,'max',2000,'sweet_min',100,'sweet_max',800),
  'growth_bonus', 6,
  'note','Mittelstand mit eigenem Kundenservice ohne Auslagerung. Wachstum/saisonale Spitzen = Bonus. Konzerne zu groß, Kleinstfirmen zu klein.'
)) on conflict (key) do nothing;
