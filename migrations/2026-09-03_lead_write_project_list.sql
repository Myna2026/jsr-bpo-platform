-- Punkt 2 (Bearbeiten): Lead-Schreib-RPCs auf die perm-Projektliste ausweiten.
-- Bisher scopten promote_employee/update_employee_lead hart auf das EINZELNE eigene Projekt
-- (get_my_employee_project_id). Fuer die gegenseitige Vertretung (Edi/Ylli, projects='list')
-- muss ein Lead alle ihm erlaubten Projekte bearbeiten koennen. Autorisierung daher ueber
-- perm_proj_ok(auth.uid(),'emp',project) - identisch zum Lesescope. Einzelprojekt-Leads
-- (projects='own') bleiben unveraendert auf ihr Projekt beschraenkt. Gehalts-/Bank-Schreibschutz
-- und alle uebrigen Regeln unveraendert. id_number wird jetzt ebenfalls aus Lead-Payloads
-- gestrichen (die fuehrung-View maskiert sie -> sonst wuerde ein Lead-Save sie mit null ueberschreiben).

CREATE OR REPLACE FUNCTION public.promote_employee(p_payload jsonb)
 RETURNS employees
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare is_adm boolean; cols text; sel text; rec public.employees;
begin
  is_adm := public.is_management() or public.is_hr() or public.is_finance();
  if not (is_adm or (public.is_planner() and public.perm_mode(auth.uid(),'emp')='edit' and public.perm_proj_ok(auth.uid(),'emp',(p_payload->>'project_id'), null))) then
    raise exception 'Nicht berechtigt, für dieses Projekt anzulegen.';
  end if;
  -- Leads dürfen keine Gehalts-/Bankdaten setzen; ID vergibt die DB.
  if not is_adm then
    p_payload := p_payload - 'fixed_salary' - 'hourly_rate' - 'salary_currency' - 'salary_type' - 'guaranteed_pct' - 'bank' - 'id_number';
  end if;
  -- Client-generierte gültige uuid behalten (optimistisches UI passt); sonst DB-Default vergeben lassen.
  if (p_payload->>'id') is null or (p_payload->>'id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    p_payload := p_payload - 'id';
  end if;
  -- Dynamische Spaltenliste: nur vorhandene Keys, die echte employees-Spalten sind (Rest fällt weg).
  select string_agg(quote_ident(k), ','), string_agg('r.'||quote_ident(k), ',')
    into cols, sel
  from jsonb_object_keys(p_payload) as t(k)
  where exists (select 1 from information_schema.columns c
                where c.table_schema='public' and c.table_name='employees' and c.column_name=t.k);
  if cols is null then raise exception 'Leere Nutzlast.'; end if;
  execute format('insert into public.employees (%s) select %s from jsonb_populate_record(null::public.employees, $1) r returning *', cols, sel)
    into rec using p_payload;
  return rec;
end $function$;


CREATE OR REPLACE FUNCTION public.update_employee_lead(p_payload jsonb)
 RETURNS employees
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare is_adm boolean; eid uuid; existing_proj text; setlist text; rec public.employees;
begin
  is_adm := public.is_management() or public.is_hr() or public.is_finance();
  if (p_payload->>'id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'id fehlt oder ungueltig.'; end if;
  eid := (p_payload->>'id')::uuid;
  select project_id into existing_proj from public.employees where id = eid;
  if not found then raise exception 'Mitarbeiter nicht gefunden.'; end if;
  if not is_adm then
    if not public.is_planner() or public.perm_mode(auth.uid(),'emp')<>'edit' or not public.perm_proj_ok(auth.uid(),'emp',existing_proj, null) then
      raise exception 'Nicht berechtigt (fremdes oder kein Projekt).'; end if;
    if (p_payload ? 'project_id') and not public.perm_proj_ok(auth.uid(),'emp',(p_payload->>'project_id'), null) then
      raise exception 'Projektwechsel nur in ein erlaubtes Projekt.'; end if;
    p_payload := p_payload - 'fixed_salary' - 'hourly_rate' - 'salary_currency' - 'salary_type' - 'guaranteed_pct' - 'bank' - 'id_number';
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
end $function$;

