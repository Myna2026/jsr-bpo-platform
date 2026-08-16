-- =============================================================================
-- Datenabfrage per Sprache — Sicherheitsfundament (Schnitt 1)
-- =============================================================================
-- AUSSCHLIESSLICH SELECT, serverseitig hart erzwungen:
--   1) Read-only-Rolle nlquery_ro: nur SELECT auf die Allowlist, default_transaction_read_only,
--      BYPASSRLS (Management ist zu allen Daten berechtigt; Zugang ist management-only).
--   2) nlquery_exec(sql): SECURITY DEFINER, prueft is_management(), validiert (eine Anweisung,
--      Beginn select/with, DDL/DML-Sperrliste), SET LOCAL ROLE nlquery_ro + read-only + Timeout,
--      wickelt die Abfrage in eine Unterabfrage mit LIMIT (jede Nicht-SELECT-Konstruktion wird
--      dadurch zum Syntaxfehler). Selbst bei ueberlisteter KI kann nichts geschrieben werden.
-- Idempotent. Nach dem Einspielen ruft die Edge Function nur diese Funktion mit dem User-JWT auf.
-- =============================================================================

do $$
declare t text; tbls text[] := array[
  'employees','kpi_config','kpi_entries','kpi_project_entries','weekly_hours','weekly_calls',
  'weekly_gauges','report_forecast','report_longterm','report_fte','report_measures','cvs',
  'absences','shift_assignments','call_criteria','call_samples','call_scores','windsor_marketing','projects'];
begin
  if not exists (select 1 from pg_roles where rolname='nlquery_ro') then create role nlquery_ro nologin; end if;
  execute 'alter role nlquery_ro set default_transaction_read_only = on';
  execute 'alter role nlquery_ro bypassrls';
  execute 'grant usage on schema public to nlquery_ro';
  foreach t in array tbls loop
    if exists (select 1 from information_schema.tables where table_schema='public' and table_name=t) then
      execute format('grant select on public.%I to nlquery_ro', t);
    end if;
  end loop;
end $$;

create or replace function public.nlquery_exec(p_sql text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v text; v_res jsonb;
begin
  if not public.is_management() then raise exception 'Nur Management darf die Datenabfrage nutzen.'; end if;
  v := btrim(coalesce(p_sql,''));
  v := regexp_replace(v, ';+\s*$', '');                     -- abschliessende Semikolons entfernen
  if v = '' then raise exception 'Leere Abfrage.'; end if;
  if position(';' in v) > 0 then raise exception 'Nur eine einzelne Anweisung erlaubt.'; end if;
  if lower(v) !~ '^(with|select)\s' then raise exception 'Nur SELECT-Abfragen erlaubt.'; end if;
  if lower(v) ~ '\y(insert|update|delete|drop|alter|truncate|grant|revoke|create|merge|copy|vacuum)\y'
    then raise exception 'Nur lesende Abfragen erlaubt (kein Schreiben).'; end if;
  set local statement_timeout = '8000';
  set local role nlquery_ro;
  execute 'select coalesce(jsonb_agg(x), ''[]''::jsonb) from (select * from ('||v||') s limit 1000) x' into v_res;
  reset role;
  return v_res;
exception when others then
  begin reset role; exception when others then null; end;
  raise;
end $$;

revoke all on function public.nlquery_exec(text) from public;
grant execute on function public.nlquery_exec(text) to authenticated;

-- Verifikation (auskommentiert, als Management ausfuehren):
-- select public.nlquery_exec('select count(*) as n from employees');           -- ok
-- select public.nlquery_exec('update employees set fixed_salary=0');            -- Fehler (Sperrliste)
-- select public.nlquery_exec('select 1; drop table employees');                -- Fehler (eine Anweisung)
