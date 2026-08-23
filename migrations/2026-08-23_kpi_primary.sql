-- Primär-KPIs: das Management markiert je Projekt/Skill die wichtigsten KPIs. Diese stehen im Cockpit groß oben
-- (mit Korridor-Balken + Ziel-Schwelle), der Rest klappt auf. Additiv, Default false (nichts ändert sich, bis markiert).
alter table public.kpi_config add column if not exists is_primary boolean not null default false;
