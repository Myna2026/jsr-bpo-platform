-- Wissensspeicher: geografische Zusammenhänge (Insel↔Ort, Region↔Stadt, Land↔Gebiet). Damit "Problem auf Kreta"
-- die Heraklion-Fakten findet, obwohl im Register nur Heraklion steht. Robuster Weg: die KI BAUT die Zuordnung
-- einmal aus den echten Zielgebieten (Edge Function kb-geo), gespeichert wird sie DETERMINISTISCH in kb_regions,
-- die Suche nutzt die feste Zuordnung (kein KI-Ratespiel zur Suchzeit). Gilt für alle bestehenden UND künftigen
-- Zielgebiete (kb-geo läuft nach dem Katalogisieren automatisch mit + manueller Aktualisieren-Knopf).

-- ── 1) Regionen-Tabelle (je Partner) ────────────────────────────────────────
create table if not exists public.kb_regions (
  id          uuid primary key default gen_random_uuid(),
  project_id  text not null references public.projects(id) on delete cascade,
  name        text not null,                       -- geläufiger Name, z. B. "Kreta"
  kind        text,                                -- insel|region|land|gebiet
  aliases     text[] not null default '{}',        -- andere Schreibweisen/Sprachen, z. B. {"Crete"}
  members     text[] not null default '{}',        -- exakte Zielgebiet-Strings, die dazugehören ("Griechenland / Heraklion")
  source      text not null default 'ki',          -- ki|manuell (manuell = von Hand angelegt/korrigiert, überlebt KI-Neuaufbau)
  status      text not null default 'active',      -- active|archived
  created_by  uuid,
  updated_by  uuid,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists kb_regions_project_idx on public.kb_regions(project_id,status);
create unique index if not exists kb_regions_uni on public.kb_regions(project_id, lower(name)) where status='active';

-- RLS wie kb_facts: Lesen = Area sichtbar + Partner erlaubt; Schreiben = Modus edit + Partner erlaubt.
alter table public.kb_regions enable row level security;
drop policy if exists kb_regions_sel on public.kb_regions;
create policy kb_regions_sel on public.kb_regions for select using (
  coalesce((public.perm(auth.uid(),'wissen')->>'visible')::boolean,false)
  and public.perm_proj_ok(auth.uid(),'wissen',project_id));
drop policy if exists kb_regions_write on public.kb_regions;
create policy kb_regions_write on public.kb_regions for all using (
  public.perm_mode(auth.uid(),'wissen')='edit'
  and public.perm_proj_ok(auth.uid(),'wissen',project_id))
  with check (
  public.perm_mode(auth.uid(),'wissen')='edit'
  and public.perm_proj_ok(auth.uid(),'wissen',project_id));
grant select, insert, update, delete on public.kb_regions to authenticated;

-- ── 2) Retrieval mit Regionen-Ausweitung ────────────────────────────────────
-- Nennt die Frage eine Region/Insel/ein Gebiet (exakt ODER unscharf), werden deren Orte in die Suche eingespeist:
-- die Ortsnamen erweitern die Frage (bessere Rangfolge der direkten Treffer) UND die Zielgebiete kommen in die
-- Übersicht. So funktioniert "Kreta Notfallnummer" (findet Heraklion) genauso wie "Problem auf Kreta" (Übersicht).
create or replace function public.kb_retrieve(p_project text, p_q text, p_limit int default 8)
returns jsonb language plpgsql stable security definer set search_path=public, extensions as $$
declare
  v_ok boolean; q tsquery; v_qx text; member_zg text[];
  v_facts jsonb; v_chunks jsonb; v_related jsonb; v_overview jsonb;
  topics text[]; zgs text[]; over_zg text[];
  FUZZ  constant real := 0.4;   -- Schwelle für Tippfehler-Ähnlichkeit (Recall-first; die KI filtert)
  ZFUZZ constant real := 0.55;  -- strengere Schwelle für Zielgebiets-/Regions-Erkennung (ein Wort)
begin
  v_ok := coalesce((public.perm(auth.uid(),'wissen')->>'visible')::boolean,false)
          and public.perm_proj_ok(auth.uid(),'wissen',p_project);
  if not v_ok then return jsonb_build_object('ok',false,'error','forbidden'); end if;

  -- ── Region in der Frage erkennen -> zugehörige Zielgebiete sammeln ──
  select coalesce(array_agg(distinct m), '{}') into member_zg from (
    select unnest(r.members) m
    from public.kb_regions r
    where r.project_id=p_project and r.status='active'
      and (
        unaccent(lower(coalesce(p_q,''))) like '%'||unaccent(lower(r.name))||'%'
        or exists (select 1 from unnest(r.aliases) a where a<>'' and unaccent(lower(coalesce(p_q,''))) like '%'||unaccent(lower(a))||'%')
        or exists (select 1 from unnest(regexp_split_to_array(unaccent(lower(coalesce(p_q,''))), '\s+')) tok
                   where length(tok) >= 4 and (
                     word_similarity(tok, unaccent(lower(r.name))) > ZFUZZ
                     or exists (select 1 from unnest(r.aliases) a where a<>'' and word_similarity(tok, unaccent(lower(a))) > ZFUZZ)
                   ))
      )
  ) mm;

  -- Erweiterte Frage: Ortsnamen der erkannten Region anhängen (nur der Ort-Teil, ohne "Land / " -> kein Rauschen).
  v_qx := coalesce(p_q,'');
  if array_length(member_zg,1) > 0 then
    v_qx := v_qx || ' ' || (select string_agg(regexp_replace(m, '^.*/\s*', ''), ' ') from unnest(member_zg) m);
  end if;

  -- ODER statt UND (ein fehlendes Wort killt den Treffer sonst). q darf null sein — Trigram/Übersicht greifen trotzdem.
  q := nullif(replace(websearch_to_tsquery('german', v_qx)::text, ' & ', ' | '), '')::tsquery;

  -- ── Register-Fakten: exakt (Wortsuche) ODER unscharf (Trigram) ──
  select coalesce(jsonb_agg(to_jsonb(x) order by x.exact desc, x.hits desc, x.rank desc, x.sim desc), '[]'::jsonb)
    into v_facts from (
    select s.* from (
      select f.id, f.topic, f.zielgebiet, f.info_type, f.label, f.value, f.qualifier,
             f.source, f.source_locator, f.valid_from, f.valid_to, d.title as source_title,
             (q is not null and to_tsvector('german',
                coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,'')||' '||coalesce(f.value,'')) @@ q) as exact,
             case when q is null then 0 else ts_rank(to_tsvector('german',
                coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,'')||' '||coalesce(f.value,'')), q) end as rank,
             public.kb_word_hits(v_qx, coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,'')||' '||coalesce(f.value,'')) as hits,
             (select coalesce(max(word_similarity(tok, unaccent(lower(
                 coalesce(f.topic,'')||' '||coalesce(f.zielgebiet,'')||' '||coalesce(f.label,''))))),0)
              from unnest(regexp_split_to_array(unaccent(lower(v_qx)), '\s+')) tok
              where length(tok) >= 4) as sim
      from public.kb_facts f
      left join public.kb_documents d on d.id=f.source_document_id
      where f.project_id=p_project and f.status='active'
    ) s
    where s.exact or s.sim > FUZZ
    order by s.exact desc, s.hits desc, s.rank desc, s.sim desc
    limit p_limit
  ) x;

  -- ── Dokument-Abschnitte: exakt ODER unscharf ──
  select coalesce(jsonb_agg(to_jsonb(y) order by y.exact desc, y.hits desc, y.rank desc, y.sim desc), '[]'::jsonb)
    into v_chunks from (
    select s.* from (
      select c.id, c.section, c.content, c.document_id, d.title as doc_title, d.doc_kind,
             (q is not null and c.tsv @@ q) as exact,
             case when q is null then 0 else ts_rank(c.tsv, q) end as rank,
             public.kb_word_hits(v_qx, c.content) as hits,
             (select coalesce(max(word_similarity(tok, unaccent(lower(c.content)))),0)
              from unnest(regexp_split_to_array(unaccent(lower(v_qx)), '\s+')) tok
              where length(tok) >= 4) as sim
      from public.kb_chunks c
      join public.kb_documents d on d.id=c.document_id
      where c.project_id=p_project and d.status='active'
    ) s
    where s.exact or s.sim > FUZZ
    order by s.exact desc, s.hits desc, s.rank desc, s.sim desc
    limit p_limit
  ) y;

  -- ── Zielgebiet(e) in der (erweiterten) Frage erkennen + erkannte Region-Zielgebiete dazunehmen ──
  select array_agg(z) into over_zg from (
    select f.zielgebiet z
    from public.kb_facts f
    where f.project_id=p_project and f.status='active' and coalesce(f.zielgebiet,'') <> ''
    group by f.zielgebiet
    having (
      unaccent(lower(v_qx)) like '%'||unaccent(lower(f.zielgebiet))||'%'
      or exists (select 1 from unnest(regexp_split_to_array(unaccent(lower(v_qx)), '\s+')) tok
                 where length(tok) >= 4 and word_similarity(tok, unaccent(lower(f.zielgebiet))) > ZFUZZ)
    )
  ) t;
  if array_length(member_zg,1) > 0 then
    over_zg := (select array_agg(distinct z) from unnest(coalesce(over_zg,'{}'::text[]) || member_zg) z);
  end if;

  -- ── Übersicht: alle Fakten der erkannten Zielgebiete (auch ohne Wort-Treffer) ──
  if over_zg is not null and array_length(over_zg,1) > 0 then
    select coalesce(jsonb_agg(to_jsonb(o) order by o.zielgebiet, o.topic), '[]'::jsonb) into v_overview from (
      select f.id, f.topic, f.zielgebiet, f.info_type, f.label, f.value, f.qualifier, f.source_locator,
             d.title as source_title
      from public.kb_facts f
      left join public.kb_documents d on d.id=f.source_document_id
      where f.project_id=p_project and f.status='active' and f.zielgebiet = any(over_zg)
      limit 80
    ) o;
  else
    v_overview := '[]'::jsonb;
  end if;

  -- ── Verwandte Fakten (Nachbarschaft der direkten Treffer) ──
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
        (f.zielgebiet is not null and v_qx ilike '%'||f.zielgebiet||'%') or
        (f.topic     is not null and v_qx ilike '%'||f.topic||'%')
      )
    limit 12
  ) z;

  return jsonb_build_object('ok',true,'facts',v_facts,'chunks',v_chunks,'related',v_related,
                            'overview',v_overview,'overview_zg',coalesce(to_jsonb(over_zg),'[]'::jsonb));
end $$;

grant execute on function public.kb_retrieve(text,text,int) to authenticated;
