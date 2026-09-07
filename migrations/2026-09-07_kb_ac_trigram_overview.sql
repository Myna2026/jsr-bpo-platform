-- Wissensspeicher Schnitt A + C — bessere Trefferquote OHNE externen Dienst (pgvector bleibt zurückgestellt).
--
-- A) Tippfehler-Toleranz: kb_retrieve matcht Fakten/Abschnitte jetzt zusätzlich UNSCHARF (pg_trgm word_similarity,
--    akzent- und großschreibungsfrei via unaccent). Fängt "Rhodus"->"Rhodos", "Stornierug"->"Stornierung" und
--    auch morphologische Varianten, die der deutsche Stemmer verfehlt ("stornieren"->"Stornierung"). Recall-first,
--    die KI filtert wie bisher und erfindet nichts.
-- C) Übersicht bei vager Frage: erkennt ein Zielgebiet in der Frage (exakt enthalten ODER unscharf) und liefert
--    ALLE aktiven Fakten dazu als `overview` — auch ohne Wort-Treffer. Damit kann der Agent bei "Problem Rhodos"
--    zeigen, was er zu Rhodos hat, statt "steht nicht drin". Der Motor entscheidet, ob konkret oder Übersicht.

create schema if not exists extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;

create or replace function public.kb_retrieve(p_project text, p_q text, p_limit int default 8)
returns jsonb language plpgsql stable security definer set search_path=public, extensions as $$
declare
  v_ok boolean; q tsquery;
  v_facts jsonb; v_chunks jsonb; v_related jsonb; v_overview jsonb;
  topics text[]; zgs text[]; over_zg text[];
  FUZZ  constant real := 0.4;   -- Schwelle für Tippfehler-Ähnlichkeit (Recall-first; die KI filtert)
  ZFUZZ constant real := 0.55;  -- strengere Schwelle für Zielgebiets-Erkennung (ein Wort)
begin
  v_ok := coalesce((public.perm(auth.uid(),'wissen')->>'visible')::boolean,false)
          and public.perm_proj_ok(auth.uid(),'wissen',p_project);
  if not v_ok then return jsonb_build_object('ok',false,'error','forbidden'); end if;

  -- ODER statt UND (ein fehlendes Wort killt den Treffer sonst). q darf null sein (nur Stoppwörter/leer) —
  -- Trigram und Übersicht können dann trotzdem greifen.
  q := nullif(replace(websearch_to_tsquery('german', coalesce(p_q,''))::text, ' & ', ' | '), '')::tsquery;

  -- ── A) Register-Fakten: exakt (Wortsuche) ODER unscharf (Trigram) ──
  select coalesce(jsonb_agg(to_jsonb(x) order by x.exact desc, x.hits desc, x.rank desc, x.sim desc), '[]'::jsonb)
    into v_facts from (
    select s.* from (
      select f.id, f.topic, f.zielgebiet, f.info_type, f.label, f.value, f.qualifier,
             f.source, f.source_locator, f.valid_from, f.valid_to, d.title as source_title,
             (q is not null and to_tsvector('german',
                coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,'')||' '||coalesce(f.value,'')) @@ q) as exact,
             case when q is null then 0 else ts_rank(to_tsvector('german',
                coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,'')||' '||coalesce(f.value,'')), q) end as rank,
             public.kb_word_hits(p_q, coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,'')||' '||coalesce(f.value,'')) as hits,
             (select coalesce(max(word_similarity(tok, unaccent(lower(
                 coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,''))))),0)
              from unnest(regexp_split_to_array(unaccent(lower(coalesce(p_q,''))), '\s+')) tok
              where length(tok) >= 4) as sim
      from public.kb_facts f
      left join public.kb_documents d on d.id=f.source_document_id
      where f.project_id=p_project and f.status='active'
    ) s
    where s.exact or s.sim > FUZZ
    order by s.exact desc, s.hits desc, s.rank desc, s.sim desc
    limit p_limit
  ) x;

  -- ── A) Dokument-Abschnitte: exakt ODER unscharf ──
  select coalesce(jsonb_agg(to_jsonb(y) order by y.exact desc, y.hits desc, y.rank desc, y.sim desc), '[]'::jsonb)
    into v_chunks from (
    select s.* from (
      select c.id, c.section, c.content, c.document_id, d.title as doc_title, d.doc_kind,
             (q is not null and c.tsv @@ q) as exact,
             case when q is null then 0 else ts_rank(c.tsv, q) end as rank,
             public.kb_word_hits(p_q, c.content) as hits,
             (select coalesce(max(word_similarity(tok, unaccent(lower(c.content)))),0)
              from unnest(regexp_split_to_array(unaccent(lower(coalesce(p_q,''))), '\s+')) tok
              where length(tok) >= 4) as sim
      from public.kb_chunks c
      join public.kb_documents d on d.id=c.document_id
      where c.project_id=p_project and d.status='active'
    ) s
    where s.exact or s.sim > FUZZ
    order by s.exact desc, s.hits desc, s.rank desc, s.sim desc
    limit p_limit
  ) y;

  -- ── C) Zielgebiet(e) in der Frage erkennen (exakt enthalten ODER unscharf) ──
  select array_agg(z) into over_zg from (
    select f.zielgebiet z
    from public.kb_facts f
    where f.project_id=p_project and f.status='active' and coalesce(f.zielgebiet,'') <> ''
    group by f.zielgebiet
    having (
      unaccent(lower(coalesce(p_q,''))) like '%'||unaccent(lower(f.zielgebiet))||'%'
      or exists (select 1 from unnest(regexp_split_to_array(unaccent(lower(coalesce(p_q,''))), '\s+')) tok
                 where length(tok) >= 4 and word_similarity(tok, unaccent(lower(f.zielgebiet))) > ZFUZZ)
    )
  ) t;

  -- ── C) Übersicht: alle Fakten der erkannten Zielgebiete (auch ohne Wort-Treffer) ──
  if over_zg is not null and array_length(over_zg,1) > 0 then
    select coalesce(jsonb_agg(to_jsonb(o) order by o.zielgebiet, o.topic), '[]'::jsonb) into v_overview from (
      select f.id, f.topic, f.zielgebiet, f.info_type, f.label, f.value, f.qualifier, f.source_locator,
             d.title as source_title
      from public.kb_facts f
      left join public.kb_documents d on d.id=f.source_document_id
      where f.project_id=p_project and f.status='active' and f.zielgebiet = any(over_zg)
      limit 60
    ) o;
  else
    v_overview := '[]'::jsonb;
  end if;

  -- ── Verwandte Fakten (Nachbarschaft der direkten Treffer) — wie bisher ──
  if q is not null then
    select array_agg(distinct topic), array_agg(distinct zielgebiet) into topics, zgs
      from public.kb_facts f
     where f.project_id=p_project and f.status='active'
       and to_tsvector('german',
             coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,'')||' '||coalesce(f.value,'')) @@ q;
  end if;

  select coalesce(jsonb_agg(to_jsonb(z)), '[]'::jsonb) into v_related from (
    select f.id, f.topic, f.zielgebiet, f.info_type, f.label, f.value, f.qualifier, f.source_locator,
           d.title as source_title
    from public.kb_facts f
    left join public.kb_documents d on d.id=f.source_document_id
    where f.project_id=p_project and f.status='active'
      and (q is null or not (to_tsvector('german',
            coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,'')||' '||coalesce(f.value,'')) @@ q))
      and (
        (f.zielgebiet is not null and f.zielgebiet = any(coalesce(zgs,array[]::text[]))) or
        (f.topic     is not null and f.topic     = any(coalesce(topics,array[]::text[]))) or
        (f.zielgebiet is not null and p_q ilike '%'||f.zielgebiet||'%') or
        (f.topic     is not null and p_q ilike '%'||f.topic||'%')
      )
    limit 12
  ) z;

  return jsonb_build_object('ok',true,'facts',v_facts,'chunks',v_chunks,'related',v_related,
                            'overview',v_overview,'overview_zg',coalesce(to_jsonb(over_zg),'[]'::jsonb));
end $$;

grant execute on function public.kb_retrieve(text,text,int) to authenticated;
