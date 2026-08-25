-- Schnitt 3: Kommentare live. meeting_note_comments in die supabase_realtime-Publication (idempotent).
do $$ begin
  if not exists (select 1 from pg_publication_tables
                 where pubname='supabase_realtime' and schemaname='public' and tablename='meeting_note_comments') then
    alter publication supabase_realtime add table public.meeting_note_comments;
  end if;
end $$;
