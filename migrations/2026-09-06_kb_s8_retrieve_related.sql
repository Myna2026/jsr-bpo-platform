-- Wissensspeicher Schnitt 8: kb_retrieve liefert zusätzlich VERWANDTE Fakten (fürs Mitdenken). Neben den
-- direkten Treffern kommen Fakten aus demselben Zielgebiet/Thema (auch wenn die Wortsuche sie nicht traf, oder
-- wenn Zielgebiet/Thema in der Frage vorkommt). Daraus schlägt die KI ungefragte, aber passende Punkte vor
-- ("Soll ich dir auch die Nummer der Agentur geben?"). Nur Vorschläge aus echtem Wissen, nichts erfunden.

-- Wörtliche Überlappung: wie viele signifikante Fragewörter (>=5 Zeichen) kommen im Text vor. Hebt bei
-- zielgebiets-getabellten Daten die zur gefragten Region passende Zeile über die vielen anderen Transfer-Zeilen.
create or replace function public.kb_word_hits(p_q text, p_text text)
returns int language sql immutable set search_path=public as $$
  select coalesce((select count(*)::int
    from unnest(regexp_split_to_array(lower(coalesce(p_q,'')), '\s+')) w
    where length(w) >= 5 and position(w in lower(coalesce(p_text,''))) > 0), 0);
$$;
grant execute on function public.kb_word_hits(text,text) to authenticated;

create or replace function public.kb_retrieve(p_project text, p_q text, p_limit int default 8)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_ok boolean; q tsquery; v_facts jsonb; v_chunks jsonb; v_related jsonb; topics text[]; zgs text[];
begin
  v_ok := coalesce((public.perm(auth.uid(),'wissen')->>'visible')::boolean,false)
          and public.perm_proj_ok(auth.uid(),'wissen',p_project);
  if not v_ok then return jsonb_build_object('ok',false,'error','forbidden'); end if;

  q := nullif(replace(websearch_to_tsquery('german', coalesce(p_q,''))::text, ' & ', ' | '), '')::tsquery;
  if q is null or numnode(q)=0 then return jsonb_build_object('ok',true,'facts','[]'::jsonb,'chunks','[]'::jsonb,'related','[]'::jsonb); end if;

  -- Direkte Treffer: Register-Fakten (Wort-Überlappung zuerst, dann ts_rank)
  select coalesce(jsonb_agg(to_jsonb(x) order by x.hits desc, x.rank desc), '[]'::jsonb) into v_facts from (
    select f.id, f.topic, f.zielgebiet, f.info_type, f.label, f.value, f.qualifier,
           f.source, f.source_locator, f.valid_from, f.valid_to, d.title as source_title,
           ts_rank(to_tsvector('german',
             coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,'')||' '||coalesce(f.value,'')), q) as rank,
           public.kb_word_hits(p_q, coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,'')||' '||coalesce(f.value,'')) as hits
    from public.kb_facts f
    left join public.kb_documents d on d.id=f.source_document_id
    where f.project_id=p_project and f.status='active'
      and to_tsvector('german',
            coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,'')||' '||coalesce(f.value,'')) @@ q
    order by hits desc, rank desc limit p_limit
  ) x;

  -- Direkte Treffer: Dokument-Abschnitte (Wort-Überlappung zuerst — hebt die richtige Zielgebiets-Zeile hoch)
  select coalesce(jsonb_agg(to_jsonb(y) order by y.hits desc, y.rank desc), '[]'::jsonb) into v_chunks from (
    select c.id, c.section, c.content, c.document_id, d.title as doc_title, d.doc_kind,
           ts_rank(c.tsv, q) as rank, public.kb_word_hits(p_q, c.content) as hits
    from public.kb_chunks c
    join public.kb_documents d on d.id=c.document_id
    where c.project_id=p_project and d.status='active' and c.tsv @@ q
    order by hits desc, rank desc limit p_limit
  ) y;

  -- Themen/Zielgebiete der direkten Fakt-Treffer sammeln (für Nachbarschaft)
  select array_agg(distinct topic), array_agg(distinct zielgebiet) into topics, zgs
    from public.kb_facts f
   where f.project_id=p_project and f.status='active'
     and to_tsvector('german',
           coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,'')||' '||coalesce(f.value,'')) @@ q;

  -- Verwandte Fakten: gleiches Zielgebiet/Thema (oder in der Frage genannt), aber KEIN direkter Treffer
  select coalesce(jsonb_agg(to_jsonb(z)), '[]'::jsonb) into v_related from (
    select f.id, f.topic, f.zielgebiet, f.info_type, f.label, f.value, f.qualifier, f.source_locator,
           d.title as source_title
    from public.kb_facts f
    left join public.kb_documents d on d.id=f.source_document_id
    where f.project_id=p_project and f.status='active'
      and not (to_tsvector('german',
            coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,'')||' '||coalesce(f.value,'')) @@ q)
      and (
        (f.zielgebiet is not null and f.zielgebiet = any(zgs)) or
        (f.topic is not null and f.topic = any(topics)) or
        (f.zielgebiet is not null and p_q ilike '%'||f.zielgebiet||'%') or
        (f.topic is not null and p_q ilike '%'||f.topic||'%')
      )
    limit 12
  ) z;

  return jsonb_build_object('ok',true,'facts',v_facts,'chunks',v_chunks,'related',v_related);
end $$;

grant execute on function public.kb_retrieve(text,text,int) to authenticated;
