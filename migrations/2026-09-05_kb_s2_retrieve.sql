-- Wissensspeicher Schnitt 2: Retrieval-RPC (Volltext, deutsch; pgvector bewusst noch nicht). Liefert die
-- besten Register-Fakten UND Dokument-Abschnitte je Partner, MIT Quelle. Zugriff = dieselbe Regel wie RLS/UI
-- (Area 'wissen' sichtbar + Partner erlaubt), geprüft über auth.uid(). SECURITY DEFINER, damit die Suche über
-- alle freigegebenen Zeilen laufen kann; der Gate steht am Anfang. Grant nur authenticated (nutzt eigene uid).

create or replace function public.kb_retrieve(p_project text, p_q text, p_limit int default 8)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_ok boolean; q tsquery; v_facts jsonb; v_chunks jsonb;
begin
  v_ok := coalesce((public.perm(auth.uid(),'wissen')->>'visible')::boolean,false)
          and public.perm_proj_ok(auth.uid(),'wissen',p_project);
  if not v_ok then return jsonb_build_object('ok',false,'error','forbidden'); end if;

  -- ODER statt UND: websearch verknüpft alle Wörter mit & (ein fehlendes Wort killt den Treffer). Für eine
  -- Wissens-Suche zu streng. Wir ODER-verknüpfen die Lexeme und ranken (ts_rank) — Recall hoch, Relevanz übers
  -- Ranking, die KI filtert und sagt sonst ehrlich "steht nicht drin".
  q := nullif(replace(websearch_to_tsquery('german', coalesce(p_q,''))::text, ' & ', ' | '), '')::tsquery;
  if q is null or numnode(q)=0 then return jsonb_build_object('ok',true,'facts','[]'::jsonb,'chunks','[]'::jsonb); end if;

  -- Register-Fakten (Präzisionskern: Nummern, Zeiten, Regeln)
  select coalesce(jsonb_agg(to_jsonb(x) order by x.rank desc), '[]'::jsonb) into v_facts from (
    select f.id, f.topic, f.zielgebiet, f.info_type, f.label, f.value, f.qualifier,
           f.source, f.source_locator, f.valid_from, f.valid_to, d.title as source_title,
           ts_rank(to_tsvector('german',
             coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,'')||' '||coalesce(f.value,'')), q) as rank
    from public.kb_facts f
    left join public.kb_documents d on d.id=f.source_document_id
    where f.project_id=p_project and f.status='active'
      and to_tsvector('german',
            coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,'')||' '||coalesce(f.value,'')) @@ q
    order by rank desc
    limit p_limit
  ) x;

  -- Dokument-Abschnitte (FAQ/Abläufe)
  select coalesce(jsonb_agg(to_jsonb(y) order by y.rank desc), '[]'::jsonb) into v_chunks from (
    select c.id, c.section, c.content, c.document_id, d.title as doc_title, d.doc_kind,
           ts_rank(c.tsv, q) as rank
    from public.kb_chunks c
    join public.kb_documents d on d.id=c.document_id
    where c.project_id=p_project and d.status='active' and c.tsv @@ q
    order by rank desc
    limit p_limit
  ) y;

  return jsonb_build_object('ok',true,'facts',v_facts,'chunks',v_chunks);
end $$;

grant execute on function public.kb_retrieve(text,text,int) to authenticated;
