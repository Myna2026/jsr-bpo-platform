-- Wissensspeicher je Partner (Condor/Holidaycheck/Giganetz/Fabletics) — Schnitt 0: Fundament. REIN ADDITIV.
-- Partner = projects-Zeilen (Text-Slug). Zwei Ebenen: kb_facts = kuratiertes Register (Präzisionskern für
-- Notfallnummern/Transferzeiten, von Hand pflegbar), kb_chunks = Volltext der Dokumente (FAQ/Abläufe).
-- Zugriff je Partner über das bestehende Rechte-Modell: neue Area 'wissen', durchgesetzt via perm_proj_ok.
-- Noch keine UI, keine Edge Function — nur Tabellen, Bucket, Rechte. pgvector bewusst NICHT (kommt später,
-- erst Volltext; die Lücken-Liste entscheidet). Mitarbeiter-Portal-Zugang folgt später (erst HR-Portal bewährt).

-- ── 1) Rechte-Area 'wissen' + Rollen-Standards ──────────────────────────────
-- Partner-Scoping über die projekt-Achse (project_ids). Keine Gehalts-/Skill-/Hierarchie-Achse.
insert into public.permission_areas(key,label,seq,axes,menu_keys) values
 ('wissen','Wissensspeicher',14,'{"gehalt":false,"projekt":true,"skill":false,"hierarchie":false}','{wissensspeicher}')
on conflict (key) do nothing;

-- Nur Back-Office/HR-Portal-Rollen. Management/HR pflegen (edit, alle Partner), finance liest alle,
-- projektleiter/teamlead lesen ihren eigenen Partner. mitarbeiter/agent/trainer/qm bleiben ungeseedet
-- -> Resolver liefert visible=false (kein Zugriff), bis sie in einem späteren Schnitt bewusst freigegeben werden.
insert into public.role_permissions(role_key,area_key,visible,mode,salary,direction,projects,skill) values
 ('management','wissen',true,'edit','none','up','all','all'),
 ('hr','wissen',true,'edit','none','up','all','all'),
 ('finance','wissen',true,'read','none','up','all','all'),
 ('projektleiter','wissen',true,'read','none','side','own','all'),
 ('teamlead','wissen',true,'read','none','down','own','all')
on conflict (role_key,area_key) do nothing;

-- ── 2) Dokumente (je hochgeladene Datei) ────────────────────────────────────
create table if not exists public.kb_documents (
  id             uuid primary key default gen_random_uuid(),
  project_id     text not null references public.projects(id) on delete cascade,
  title          text,
  original_name  text,
  storage_path   text unique,
  mime_type      text,
  size_bytes     bigint,
  doc_kind       text,                         -- agb|faq|zielgebiet|produkt|ablauf|sonstiges (grob)
  summary        text,                         -- Kurz-Zusammenfassung (worum geht es)
  version        int  not null default 1,
  supersedes     uuid references public.kb_documents(id) on delete set null,  -- ersetzte Vorfassung
  status         text not null default 'active',  -- active|superseded|archived
  uploaded_by    uuid,
  created_at     timestamptz not null default now()
);
create index if not exists kb_documents_project_idx on public.kb_documents(project_id);
create index if not exists kb_documents_status_idx on public.kb_documents(project_id,status);

-- ── 3) Volltext-Chunks (Absätze mit Fundstelle) ─────────────────────────────
create table if not exists public.kb_chunks (
  id           uuid primary key default gen_random_uuid(),
  document_id  uuid not null references public.kb_documents(id) on delete cascade,
  project_id   text not null references public.projects(id) on delete cascade,
  ord          int  not null default 0,
  section      text,                          -- Überschrift/Abschnitt
  page         int,                           -- Seite (bei PDF)
  content      text not null,
  tsv          tsvector generated always as (to_tsvector('german', coalesce(content,''))) stored,
  created_at   timestamptz not null default now()
);
create index if not exists kb_chunks_tsv_idx on public.kb_chunks using gin(tsv);
create index if not exists kb_chunks_project_idx on public.kb_chunks(project_id);
create index if not exists kb_chunks_document_idx on public.kb_chunks(document_id);

-- ── 4) Register (kuratierte Fakten, von Hand oder aus Dateien) ───────────────
create table if not exists public.kb_facts (
  id                 uuid primary key default gen_random_uuid(),
  project_id         text not null references public.projects(id) on delete cascade,
  topic              text not null,               -- Thema (z.B. "Notfallnummer", "Transfer")
  zielgebiet         text,                        -- z.B. "Rhodos", "Mallorca" (optional)
  info_type          text,                        -- kontakt|zeit|ablauf|regel|preis|sonstiges
  label              text not null,               -- kurzer Titel des Eintrags
  value              text not null,               -- der eigentliche Wert / die Antwort
  qualifier          jsonb not null default '{}', -- Unterscheidung: {saison, veranstalter, ...}
  source             text not null default 'manual', -- manual|file
  source_document_id uuid references public.kb_documents(id) on delete set null,
  source_locator     text,                        -- Fundstelle (Seite/Abschnitt)
  confidence         text not null default 'confirmed', -- confirmed|proposed
  status             text not null default 'active',    -- active|archived
  valid_from         date,
  valid_to           date,
  first_seen_at      timestamptz not null default now(), -- wann ins System gekommen
  created_by         uuid,
  updated_by         uuid,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index if not exists kb_facts_project_idx on public.kb_facts(project_id,status);
create index if not exists kb_facts_topic_idx on public.kb_facts(project_id,topic);
create index if not exists kb_facts_zielgebiet_idx on public.kb_facts(project_id,zielgebiet);

-- ── 5) RLS: Lesen = Area sichtbar + Partner erlaubt; Schreiben = Modus 'edit' + Partner erlaubt ──
-- Management/HR (projects='all') sehen/pflegen alle Partner; Leads nur ihren eigenen; ungeseedete Rollen nichts.
alter table public.kb_documents enable row level security;
alter table public.kb_chunks    enable row level security;
alter table public.kb_facts     enable row level security;

do $$
declare t text;
begin
  foreach t in array array['kb_documents','kb_chunks','kb_facts'] loop
    execute format('drop policy if exists %I_sel on public.%I', t, t);
    execute format($p$create policy %1$I_sel on public.%1$I for select using (
      coalesce((public.perm(auth.uid(),'wissen')->>'visible')::boolean,false)
      and public.perm_proj_ok(auth.uid(),'wissen',project_id))$p$, t);
    execute format('drop policy if exists %I_write on public.%I', t, t);
    execute format($p$create policy %1$I_write on public.%1$I for all using (
      public.perm_mode(auth.uid(),'wissen')='edit'
      and public.perm_proj_ok(auth.uid(),'wissen',project_id))
      with check (
      public.perm_mode(auth.uid(),'wissen')='edit'
      and public.perm_proj_ok(auth.uid(),'wissen',project_id))$p$, t);
  end loop;
end $$;

grant select, insert, update, delete on public.kb_documents, public.kb_chunks, public.kb_facts to authenticated;

-- ── 6) Privater Storage-Bucket für die Quelldateien ─────────────────────────
-- Zugriff über RLS am ersten Pfad-Segment (= project_id), wie bei employee-docs. 25 MB.
-- MIME nicht hart begrenzt (CSV/Office-Formate melden uneinheitliche Typen) -> Prüfung clientseitig.
insert into storage.buckets (id,name,public,file_size_limit)
  values ('partner-knowledge','partner-knowledge',false,26214400)
on conflict (id) do update set public=false, file_size_limit=26214400;

drop policy if exists "partner_knowledge read" on storage.objects;
create policy "partner_knowledge read" on storage.objects for select using (
  bucket_id='partner-knowledge'
  and coalesce((public.perm(auth.uid(),'wissen')->>'visible')::boolean,false)
  and public.perm_proj_ok(auth.uid(),'wissen',(storage.foldername(name))[1]));

drop policy if exists "partner_knowledge write" on storage.objects;
create policy "partner_knowledge write" on storage.objects for all using (
  bucket_id='partner-knowledge'
  and public.perm_mode(auth.uid(),'wissen')='edit'
  and public.perm_proj_ok(auth.uid(),'wissen',(storage.foldername(name))[1]))
  with check (
  bucket_id='partner-knowledge'
  and public.perm_mode(auth.uid(),'wissen')='edit'
  and public.perm_proj_ok(auth.uid(),'wissen',(storage.foldername(name))[1]));
