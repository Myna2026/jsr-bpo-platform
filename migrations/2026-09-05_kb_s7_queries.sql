-- Wissensspeicher Schnitt 7: Lern-Mechanik (ehrlich = Mechanik + menschliche Pflege, das Modell lernt NICHT
-- von selbst). Jede Frage wird protokolliert: was gefragt wurde, ob es eine Antwort gab, welche Quelle half.
-- Daraus: Lücken-Liste (known=false -> Vorlage für den nächsten Upload), häufige Fragen, und "war falsch"-
-- Rückmeldungen (Widerspruch) zur Korrektur. Zugriff je Partner wie überall (perm 'wissen').

create table if not exists public.kb_queries (
  id             uuid primary key default gen_random_uuid(),
  project_id     text not null references public.projects(id) on delete cascade,
  user_id        uuid,
  question       text not null,
  known          boolean not null default false,
  had_rueckfrage boolean not null default false,
  fact_count     int not null default 0,
  chunk_count    int not null default 0,
  answer         text,
  sources        text[],
  helpful        boolean,               -- true = hat geholfen, false = war falsch (Widerspruch), null = keine Rückmeldung
  feedback_note  text,
  feedback_by    uuid,
  feedback_at    timestamptz,
  created_at     timestamptz not null default now()
);
create index if not exists kb_queries_project_idx on public.kb_queries(project_id, created_at desc);
create index if not exists kb_queries_gap_idx on public.kb_queries(project_id, known);

alter table public.kb_queries enable row level security;
drop policy if exists kb_queries_sel on public.kb_queries;
create policy kb_queries_sel on public.kb_queries for select using (
  coalesce((public.perm(auth.uid(),'wissen')->>'visible')::boolean,false)
  and public.perm_proj_ok(auth.uid(),'wissen',project_id));
-- Insert läuft über die Edge Function (Service-Role, umgeht RLS). Kein Insert/Update für authenticated nötig;
-- Rückmeldungen laufen über die RPC unten.
grant select on public.kb_queries to authenticated;

-- Rückmeldung zu einer Antwort (half / war falsch). Erlaubt für den Fragenden selbst oder wer den Partner sieht.
create or replace function public.kb_feedback(p_query uuid, p_helpful boolean, p_note text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  update public.kb_queries
     set helpful=p_helpful, feedback_note=p_note, feedback_by=auth.uid(), feedback_at=now()
   where id=p_query
     and (user_id=auth.uid() or public.perm_proj_ok(auth.uid(),'wissen',project_id));
end $$;
grant execute on function public.kb_feedback(uuid,boolean,text) to authenticated;
