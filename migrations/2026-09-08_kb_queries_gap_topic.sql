-- Wissensspeicher: Themen-Lücke trotz Orts-Übersicht. Seit der Zielgebiets-Übersicht + Region-Ausweitung
-- antwortet der Agent bei Ortsbezug fast immer mit known=true (er zeigt, was er zum Ort hat). Damit fiele eine
-- Frage nach einem konkreten Thema, zu dem wir NICHTS haben ("Waldbrand auf Kreta"), aus der Lückenliste —
-- obwohl genau das fehlt. Der Motor meldet daher zusätzlich das nicht abgedeckte konkrete Thema in 'gap_topic';
-- der Lücken-Tab zeigt es, auch wenn nebenbei eine Übersicht ausgegeben wurde. So sehen wir, was beim Partner
-- anzufragen ist.
alter table public.kb_queries add column if not exists gap_topic text;
create index if not exists kb_queries_gaptopic_idx on public.kb_queries(project_id) where gap_topic is not null;
