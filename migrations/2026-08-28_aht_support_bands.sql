-- AHT (support) war binär (Sehr gut ≤6,3 / Kritisch >6,3) — bei einer Zeitkennzahl unsinnig: 7,5 landete
-- in derselben Schublade wie 12,88. Mittelbänder ergänzt (Vorschlag, im KPI-Admin editierbar).
-- Wirkung: 7,5 -> Gut (nicht mehr "schwach"), 10,63 -> Schlecht, 12,88 -> Kritisch.
update public.kpi_config set thresholds = '[
  {"label":"Sehr gut","min":0,"max":6.3,"color":"#229701","bg":"#22970122","icon":"🌟"},
  {"label":"Gut","min":6.31,"max":8,"color":"#4bd910","bg":"#4bd91022","icon":""},
  {"label":"Ausbaufähig","min":8.01,"max":10,"color":"#edd168","bg":"#edd16822","icon":""},
  {"label":"Schlecht","min":10.01,"max":12,"color":"#f96271","bg":"#f9627122","icon":""},
  {"label":"Kritisch","min":12.01,"max":100,"color":"#f9051e","bg":"#f9051e22","icon":""}
]'::jsonb
where id='kpi_1784716053946';
