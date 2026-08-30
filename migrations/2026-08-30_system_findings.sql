-- Maya System-Watch, Schnitt 1: Fund-Speicher + Scan.
-- Erkennt DB-seitige Auffälligkeiten (tot/leer/no-op/widersprüchlich), mit Beleg (was, seit, was hängt dran),
-- Dringlichkeit (blocking vs cosmetic). Dedup über stabilen fkey; Erledigtes wird automatisch aufgelöst.
-- KEINE Einblendung, nur abrufbar/gemeldet. Slack nur bei neuen blockierenden Funden (einmal).
create table if not exists public.system_findings(
  fkey        text primary key,            -- stabiler Schlüssel je Fund (Dedup + Erledigt-Erkennung)
  category    text not null,               -- no_op_import | config_conflict | empty_table | ...
  severity    text not null default 'cosmetic',   -- blocking | cosmetic
  title       text not null,
  evidence    jsonb not null default '{}', -- {was, seit?, haengt_dran}
  first_seen  timestamptz not null default now(),
  last_seen   timestamptz not null default now(),
  resolved_at timestamptz,
  notified_at timestamptz,                 -- Slack (blockierend) einmal
  digested_at timestamptz,                 -- in einer Mail berichtet (cosmetic einmal)
  created_at  timestamptz not null default now()
);
alter table public.system_findings enable row level security;
drop policy if exists system_findings_read on public.system_findings;
create policy system_findings_read on public.system_findings for select using (public.is_management());
grant select on public.system_findings to authenticated;

create or replace function public.maya_system_scan()
returns jsonb language plpgsql security definer set search_path=public as $$
declare r record; cnt bigint; cur text[] := '{}'; nb jsonb;
  -- Tabellen, bei denen „leer" gesund ist (Logs/Sicherheit/optionale Protokolle) → nicht als Fund werten.
  excl text[] := array['system_findings','time_pin_attempts','dm_reads','activity_log','data_imports'];
begin
  -- 1) No-op-Importe: Status ok, aber nichts geschrieben/zugeordnet (blockierend).
  for r in select id, coalesce(nullif(btrim(file_name),''),source_type) nm, source_type, kw, created_at
             from public.data_imports
            where lower(coalesce(status,'')) in ('ok','success','done','ready','fertig')
              and coalesce(matched_count, row_count, 0) = 0 loop
    cur := cur || ('noop_import:'||r.id);
    insert into public.system_findings(fkey,category,severity,title,evidence) values(
      'noop_import:'||r.id,'no_op_import','blocking',
      'Import „'||coalesce(r.nm,'?')||'" meldete Erfolg, hat aber nichts geschrieben',
      jsonb_build_object('was',coalesce(r.nm,'?')||' ('||coalesce(r.source_type,'?')||', KW '||coalesce(r.kw::text,'?')||')',
                         'seit',r.created_at::date,'haengt_dran','die daraus gespeisten Auswertungen bleiben leer'))
    on conflict(fkey) do update set last_seen=now(), resolved_at=null;
  end loop;

  -- 2) Einstellungs-Widerspruch: derselbe Menüpunkt für einen Nutzer zugleich gesperrt UND freigegeben.
  for r in
    with locks  as (select key u, value v from jsonb_each(coalesce((select value from public.app_config where key='jsr_hr_tab_locks_v1'),'{}'::jsonb))),
         grants as (select key u, value v from jsonb_each(coalesce((select value from public.app_config where key='jsr_menu_grants_v1'),'{}'::jsonb)))
    select l.u as uid, t.tab
    from locks l join grants g on g.u=l.u
    cross join lateral (
      select x.tab from jsonb_array_elements_text(l.v) x(tab)
      intersect
      select y.tab from jsonb_array_elements_text(g.v) y(tab)
    ) t loop
    cur := cur || ('conflict_tab:'||r.uid||':'||r.tab);
    insert into public.system_findings(fkey,category,severity,title,evidence) values(
      'conflict_tab:'||r.uid||':'||r.tab,'config_conflict','cosmetic',
      'Menüpunkt „'||r.tab||'" ist für einen Nutzer gleichzeitig gesperrt und freigegeben',
      jsonb_build_object('was','Tab '||r.tab||' bei Nutzer '||r.uid,
                         'haengt_dran','die Freigabe gewinnt, die Sperre ist wirkungslos, das ist verwirrend'))
    on conflict(fkey) do update set last_seen=now(), resolved_at=null;
  end loop;

  -- 3) Leere Tabellen (ECHTE Zählung, pg_stat ist hier veraltet). Cosmetic; erst über Persistenz im Digest.
  for r in select tablename from pg_tables where schemaname='public' and tablename <> all(excl) loop
    execute format('select count(*) from public.%I', r.tablename) into cnt;
    if cnt = 0 then
      cur := cur || ('empty_table:'||r.tablename);
      insert into public.system_findings(fkey,category,severity,title,evidence) values(
        'empty_table:'||r.tablename,'empty_table','cosmetic',
        'Tabelle „'||r.tablename||'" ist leer, es wird nichts hineingeschrieben',
        jsonb_build_object('was','public.'||r.tablename,
                           'haengt_dran','wird derzeit von niemandem befüllt, evtl. tot oder ungenutzt'))
      on conflict(fkey) do update set last_seen=now(), resolved_at=null;
    end if;
  end loop;

  -- Erledigt: offene Funde, deren Bedingung nicht mehr auftritt (keine Wiederholung von Behobenem).
  update public.system_findings set resolved_at=now()
   where resolved_at is null and not (fkey = any(cur));

  -- Neue blockierende Funde (noch nicht per Slack gemeldet) für den Sofort-Kanal zurückgeben.
  select coalesce(jsonb_agg(jsonb_build_object('fkey',fkey,'title',title,'evidence',evidence) order by first_seen),'[]'::jsonb)
    into nb from public.system_findings
   where severity='blocking' and resolved_at is null and notified_at is null;
  return jsonb_build_object('scanned',coalesce(array_length(cur,1),0),'new_blocking',nb);
end $$;

revoke all on function public.maya_system_scan() from public;
grant execute on function public.maya_system_scan() to service_role;
