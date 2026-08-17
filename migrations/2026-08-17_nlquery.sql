-- =============================================================================
-- Datenabfrage per Sprache — Sicherheitsfundament (Schnitt 1, Variante A)
-- =============================================================================
-- AUSSCHLIESSLICH SELECT, serverseitig hart erzwungen. Die Leseschranke haengt
-- daran, dass die Funktion der Rolle nlquery_ro GEHOERT und darum mit deren
-- Rechten laeuft: nlquery_ro hat NUR USAGE + SELECT auf die Allowlist, KEIN
-- CREATE, keine Schreibrechte. Jeder Schreibversuch scheitert an fehlenden
-- Grants (permission denied), zusaetzlich zu Regex-Pruefung (eine Anweisung,
-- Beginn select/with, DDL/DML-Sperrliste) und Wrap in eine Unterabfrage mit
-- LIMIT (Nicht-SELECT wird zum Syntaxfehler). BYPASSRLS ist gewollt: Zugang ist
-- management-only und geprueft.
--
-- Idempotent. Der Eigentuemer-Tanz weiter unten ist noetig, weil (a) CREATE OR
-- REPLACE auf einer nlquery_ro-eigenen Funktion sonst scheitert und (b) Postgres
-- beim Umhaengen verlangt, dass der NEUE Eigentuemer CREATE im Schema hat.
-- =============================================================================

do $$
declare t text; tbls text[] := array[
  'employees','kpi_config','kpi_entries','kpi_project_entries','weekly_hours','weekly_calls',
  'weekly_gauges','report_forecast','report_longterm','report_fte','report_measures','cvs',
  'absences','shift_assignments','call_criteria','call_samples','call_scores','windsor_marketing','projects'];
begin
  if not exists (select 1 from pg_roles where rolname='nlquery_ro') then create role nlquery_ro nologin; end if;
  execute 'alter role nlquery_ro bypassrls';
  execute 'alter role nlquery_ro set default_transaction_read_only = on';
  execute 'grant usage on schema public to nlquery_ro';
  foreach t in array tbls loop
    if exists (select 1 from information_schema.tables where table_schema='public' and table_name=t) then
      execute format('grant select on public.%I to nlquery_ro', t);
    end if;
  end loop;
  -- nlquery_ro fuehrt spaeter den Auth-Check selbst aus:
  execute 'grant execute on function public.is_management() to nlquery_ro';
  -- damit der aktuelle User Eigentum von/zu nlquery_ro umhaengen darf (Mitglied der Rolle):
  execute 'grant nlquery_ro to '||current_user;
  -- Falls die Funktion schon existiert und nlquery_ro gehoert: Eigentum zurueck auf den
  -- aktuellen (privilegierten) User, sonst scheitert das folgende CREATE OR REPLACE.
  if exists (select 1 from pg_proc where proname='nlquery_exec' and pronamespace='public'::regnamespace) then
    execute 'alter function public.nlquery_exec(text) owner to '||current_user;
  end if;
end $$;

create or replace function public.nlquery_exec(p_sql text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v text; v_res jsonb;
begin
  if not public.is_management() then raise exception 'Nur Management darf die Datenabfrage nutzen.'; end if;
  v := btrim(coalesce(p_sql,''));
  v := regexp_replace(v, ';+\s*$', '');
  if v = '' then raise exception 'Leere Abfrage.'; end if;
  if position(';' in v) > 0 then raise exception 'Nur eine einzelne Anweisung erlaubt.'; end if;
  if lower(v) !~ '^(with|select)\s' then raise exception 'Nur SELECT-Abfragen erlaubt.'; end if;
  if lower(v) ~ '\y(insert|update|delete|drop|alter|truncate|grant|revoke|create|merge|copy|vacuum)\y'
    then raise exception 'Nur lesende Abfragen erlaubt (kein Schreiben).'; end if;
  set local statement_timeout = '8000';
  execute 'select coalesce(jsonb_agg(x), ''[]''::jsonb) from (select * from ('||v||') s limit 1000) x' into v_res;
  return v_res;
end $$;

-- Eigentum auf nlquery_ro haengen. Der neue Eigentuemer braucht dafuer CREATE im Schema:
-- nur fuer diesen Schritt gewaehren, direkt danach wieder entziehen (nlquery_ro bleibt ohne CREATE).
grant create on schema public to nlquery_ro;
alter function public.nlquery_exec(text) owner to nlquery_ro;
revoke create on schema public from nlquery_ro;

revoke all on function public.nlquery_exec(text) from public;
grant execute on function public.nlquery_exec(text) to authenticated;

-- Verifikation (als Management ausfuehren):
-- select public.nlquery_exec('select count(*) as n from employees');   -- ok
-- select public.nlquery_exec('update employees set fixed_salary=0');   -- Fehler: kein Schreiben
-- select public.nlquery_exec('select * from app_users');               -- Fehler: permission denied
-- select public.nlquery_exec('select 1; drop table employees');        -- Fehler: eine Anweisung
