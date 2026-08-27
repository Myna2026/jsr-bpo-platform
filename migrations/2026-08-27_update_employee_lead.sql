-- Lead-Update auf employees (Statuswechsel „Produktiv setzen", Feld-Edits im eigenen Projekt). Zwei Wände:
--   1) RETURNING/.select() braucht SELECT-Sichtbarkeit (Leads fehlt) -> RPC als SECURITY DEFINER.
--   2) Trigger protect_salary_on_update macht fuer is_lead_only() NEW:=OLD (nur Abwesenheiten durch) -> jeder
--      andere Lead-Update wird zurueckgedreht. Loesung: die RPC vettet den Write (eigenes Projekt, Gehalt/Bank
--      raus) und setzt eine GUC, die der Trigger als Freigabe erkennt und den Lead-Revert ueberspringt. Die
--      Gehalts-/Vertrags-Schutzklausel bleibt zusaetzlich aktiv.

-- Trigger: Lead-Revert nur wenn NICHT die vettete RPC laeuft (GUC app.lead_employee_write='1').
create or replace function public.protect_salary_on_update() returns trigger
language plpgsql security definer set search_path=public as $$
declare v_abs jsonb;
begin
  if public.is_lead_only() and coalesce(current_setting('app.lead_employee_write', true),'') <> '1' then
    v_abs := to_jsonb(NEW)->'absences';
    NEW := OLD; NEW.absences := coalesce(v_abs, OLD.absences); NEW.updated_at := now();
    return NEW;
  end if;
  if public.is_protected_employee(NEW.id) and not (public.is_management() or public.is_finance()) then
    NEW.fixed_salary:=OLD.fixed_salary; NEW.hourly_rate:=OLD.hourly_rate; NEW.salary_currency:=OLD.salary_currency;
    NEW.bank:=OLD.bank; NEW.contract:=OLD.contract; NEW.id_number:=OLD.id_number;
  end if;
  return NEW;
end $$;

-- RPC: Update by id. Admin = frei; Lead = nur eigenes Projekt, ohne Gehalt/Bank, kein Projektwechsel; setzt die
-- GUC, damit der obige Trigger den Write durchlaesst. Gibt die Zeile zurueck (Definer umgeht die SELECT-Wand).
create or replace function public.update_employee_lead(p_payload jsonb) returns public.employees
language plpgsql security definer set search_path=public as $$
declare is_adm boolean; eid uuid; existing_proj text; setlist text; rec public.employees;
begin
  is_adm := public.is_management() or public.is_hr() or public.is_finance();
  if (p_payload->>'id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'id fehlt oder ungueltig.'; end if;
  eid := (p_payload->>'id')::uuid;
  select project_id into existing_proj from public.employees where id = eid;
  if not found then raise exception 'Mitarbeiter nicht gefunden.'; end if;
  if not is_adm then
    if not public.is_planner() or existing_proj is distinct from public.get_my_employee_project_id() then
      raise exception 'Nicht berechtigt (fremdes oder kein Projekt).'; end if;
    if (p_payload ? 'project_id') and (p_payload->>'project_id') is distinct from public.get_my_employee_project_id() then
      raise exception 'Projektwechsel nicht erlaubt.'; end if;
    p_payload := p_payload - 'fixed_salary' - 'hourly_rate' - 'salary_currency' - 'salary_type' - 'guaranteed_pct' - 'bank';
    perform set_config('app.lead_employee_write', '1', true);   -- Trigger-Bypass fuer den gevetteten Lead-Write
  end if;
  p_payload := p_payload - 'id';
  select string_agg(quote_ident(k)||'=r.'||quote_ident(k), ',') into setlist
  from jsonb_object_keys(p_payload) as t(k)
  where exists (select 1 from information_schema.columns c
               where c.table_schema='public' and c.table_name='employees' and c.column_name=t.k);
  if setlist is null then select * into rec from public.employees where id = eid; return rec; end if;
  execute format('update public.employees e set %s from jsonb_populate_record(null::public.employees, $1) r where e.id = $2 returning e.*', setlist)
    into rec using p_payload, eid;
  return rec;
end $$;
grant execute on function public.update_employee_lead(jsonb) to authenticated, service_role;
