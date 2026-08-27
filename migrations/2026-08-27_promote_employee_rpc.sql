-- Promote/Anlegen eines Mitarbeiters, leadtauglich. Grund: saveEmployeeToDB nutzt upsert().select() — die
-- RETURNING-Klausel braucht SELECT-Sichtbarkeit, die reine Projektleiter NICHT haben (nur management/finance).
-- Der direkte INSERT (employees_insert_lead) läuft, aber die Rückgabe scheitert. Darum als SECURITY-DEFINER-RPC
-- (wie set_employee_absences): fügt ein und gibt die Zeile zurück, umgeht dabei die RLS — Berechtigung wird
-- selbst geprüft. Leads: nur eigenes Projekt, sensible Spalten (Gehalt/Bank) werden verworfen.
create or replace function public.promote_employee(p_payload jsonb) returns public.employees
language plpgsql security definer set search_path = public as $$
declare is_adm boolean; cols text; sel text; rec public.employees;
begin
  is_adm := public.is_management() or public.is_hr() or public.is_finance();
  if not (is_adm or (public.is_planner() and (p_payload->>'project_id') = public.get_my_employee_project_id())) then
    raise exception 'Nicht berechtigt, für dieses Projekt anzulegen.';
  end if;
  -- Leads dürfen keine Gehalts-/Bankdaten setzen; ID vergibt die DB.
  if not is_adm then
    p_payload := p_payload - 'fixed_salary' - 'hourly_rate' - 'salary_currency' - 'salary_type' - 'guaranteed_pct' - 'bank';
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
end $$;
grant execute on function public.promote_employee(jsonb) to authenticated, service_role;
