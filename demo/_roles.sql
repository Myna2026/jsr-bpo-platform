-- Custom-Rollen, die der Schema-Dump referenziert (existieren im echten Projekt, nicht im frischen Myna).
-- Für die Demo reicht die Existenz + NOLOGIN; die konkreten Grants kommen aus dem Schema-Dump.
do $$ begin
  if not exists (select 1 from pg_roles where rolname='agent_ro') then create role agent_ro nologin; end if;
  if not exists (select 1 from pg_roles where rolname='nlquery_ro') then create role nlquery_ro nologin; end if;
end $$;
grant usage on schema public to agent_ro, nlquery_ro;
-- CREATE nötig, weil zwei Funktionen diesen Rollen gehören (neuer Owner braucht CREATE im Schema).
grant create on schema public to agent_ro, nlquery_ro;
-- Damit die ausführende Rolle den OWNER zweier Funktionen auf diese Rollen setzen kann (SET ROLE-Mitgliedschaft).
grant agent_ro to postgres;
grant nlquery_ro to postgres;
do $$ begin
  execute 'grant agent_ro to '||current_user;
  execute 'grant nlquery_ro to '||current_user;
exception when others then null; end $$;
