-- =============================================================================
-- Echte Agenten-Kommunikation (Frage -> Antwort aus eigenen Daten -> Schluss)
-- Ausführungsweg für den Antwort-Zug: agent_query_exec.
-- =============================================================================
-- Wie nlquery_exec, aber (a) OHNE is_management()-Gate (die Agenten laufen im
-- Cron als service_role, es gibt keinen Nutzer) und (b) mit eigener Rolle
-- agent_ro und breiterer Domänen-Allowlist, damit die NL-Abfrage-Fläche
-- (nlquery_ro) unverändert bleibt. Harte Leseschranke identisch: die Funktion
-- GEHÖRT agent_ro, das NUR USAGE + SELECT auf die Allowlist hat, KEIN Schreiben,
-- kein CREATE. Zusätzlich Regex (eine Anweisung, Beginn select/with, DDL/DML-
-- Sperrliste) + read-only-Rolle + Wrap mit LIMIT. Ausführbar NUR für service_role.
-- Idempotent. Der Eigentümer-Tanz ist nötig wie bei nlquery_exec.
-- =============================================================================

do $$
declare t text; tbls text[] := array[
  -- Clara (Recruiting)
  'cvs','windsor_marketing','windsor_leads',
  -- Max (Aufgaben/Datenvollständigkeit) + Paul (Analyse)
  'data_imports','report_forecast','report_longterm','report_fte','report_measures',
  'weekly_hours','weekly_calls','weekly_gauges','shift_assignments','staffing_forecast_cache',
  'kpi_config','kpi_entries','kpi_project_entries','call_criteria','call_samples','call_scores',
  -- Maya (Nutzung)
  'activity_log','app_users',
  -- Anna (Wissen)
  'assistant_gaps','app_config',
  -- Lena (Mitarbeiterstamm)
  'employees',
  -- gemeinsam
  'projects','agent_checks','agent_observations'];
begin
  if not exists (select 1 from pg_roles where rolname='agent_ro') then create role agent_ro nologin; end if;
  execute 'alter role agent_ro bypassrls';
  execute 'alter role agent_ro set default_transaction_read_only = on';
  execute 'grant usage on schema public to agent_ro';
  foreach t in array tbls loop
    if exists (select 1 from information_schema.tables where table_schema='public' and table_name=t) then
      execute format('grant select on public.%I to agent_ro', t);
    end if;
  end loop;
  execute 'grant agent_ro to '||current_user;
  if exists (select 1 from pg_proc where proname='agent_query_exec' and pronamespace='public'::regnamespace) then
    execute 'alter function public.agent_query_exec(text) owner to '||current_user;
  end if;
end $$;

create or replace function public.agent_query_exec(p_sql text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v text; v_res jsonb;
begin
  v := btrim(coalesce(p_sql,''));
  v := regexp_replace(v, ';+\s*$', '');
  if v = '' then raise exception 'Leere Abfrage.'; end if;
  if position(';' in v) > 0 then raise exception 'Nur eine einzelne Anweisung erlaubt.'; end if;
  if lower(v) !~ '^(with|select)\s' then raise exception 'Nur SELECT-Abfragen erlaubt.'; end if;
  if lower(v) ~ '\y(insert|update|delete|drop|alter|truncate|grant|revoke|create|merge|copy|vacuum)\y'
    then raise exception 'Nur lesende Abfragen erlaubt (kein Schreiben).'; end if;
  set local statement_timeout = '8000';
  execute 'select coalesce(jsonb_agg(x), ''[]''::jsonb) from (select * from ('||v||') s limit 200) x' into v_res;
  return v_res;
end $$;

grant create on schema public to agent_ro;
alter function public.agent_query_exec(text) owner to agent_ro;
revoke create on schema public from agent_ro;

revoke all on function public.agent_query_exec(text) from public;
grant execute on function public.agent_query_exec(text) to service_role;

-- Tagesdeckel für die Austausche (Start bei 3, bei Rauschen zurückdrehen).
insert into public.app_config(key, value)
values ('jsr_agent_dialogue_v1', '{"max_per_day":3}'::jsonb)
on conflict (key) do nothing;

-- Verifikation (als service_role bzw. Eigentümer):
-- select public.agent_query_exec('select count(*) as n from cvs');            -- ok
-- select public.agent_query_exec('update employees set fixed_salary=0');      -- Fehler: kein Schreiben
-- select public.agent_query_exec('select 1; drop table employees');          -- Fehler: eine Anweisung
