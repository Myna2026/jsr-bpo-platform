-- Lena meldet: Bewerber in einer Mitarbeiter-Phase ohne Mitarbeiter-Datensatz (steckengebliebene Übernahme).
-- Hintergrund: eine erfolgreiche Übernahme (promoteToEmployee) LÖSCHT den cvs-Datensatz und legt eine employees-Zeile
-- an. Bleibt eine cvs-Zeile in einer Mitarbeiter-Phase stehen, ist die Übernahme nie durchgelaufen (z.B. Status im
-- CV-Formular direkt gesetzt — nur status='active' löst die Übernahme aus, contract/training_planned/training nicht).
-- Solche Personen fehlen im Team/Mitarbeiter-Bereich, obwohl ihr Status sie dort verortet. Bislang fiel das niemandem
-- auf. Additive Ergänzung der bestehenden lena_scan-Checks, sonst unverändert.
create or replace function public.lena_scan()
 returns table(category text, severity text, employee_id uuid, name text, label text, detail text)
 language plpgsql stable security definer set search_path to 'public'
as $function$
declare emp_status text[] := array['contract','training_planned','training','active','inactive','freigestellt'];
begin
  if auth.uid() is not null and not public.is_admin() then raise exception 'not authorized'; end if;
  return query
  select 'vertrag_ohne_daten','hoch', e.id, trim(coalesce(e.first_name,'')||' '||coalesce(e.last_name,'')),
         'Vertragsbeginn fehlt', coalesce(e.position,'')
  from public.employees e
  where e.status = any(emp_status) and coalesce(nullif(e.contract->>'start',''), '') = ''
  union all
  select 'ausweis_fehlt','mittel', e.id, trim(coalesce(e.first_name,'')||' '||coalesce(e.last_name,'')),
         'Ausweis-Nummer fehlt', coalesce(e.position,'')
  from public.employees e
  where e.status = any(emp_status) and coalesce(nullif(e.id_number,''), '') = ''
  union all
  select 'bank_fehlt','mittel', e.id, trim(coalesce(e.first_name,'')||' '||coalesce(e.last_name,'')),
         'Bankverbindung fehlt', coalesce(e.position,'')
  from public.employees e
  where e.status in ('training','active','inactive','freigestellt') and coalesce(nullif(e.bank->>'iban',''), '') = ''
  union all
  select 'urlaubsantrag_liegt','mittel', vr.employee_id, vr.employee_name,
         'Urlaubsantrag liegt seit '||extract(day from now()-vr.created_at)::int||' Tagen',
         to_char(vr.from_date,'DD.MM.')||'–'||to_char(vr.to_date,'DD.MM.')
  from public.vacation_requests vr
  where coalesce(vr.status,'') not in ('approved','rejected','cancelled','withdrawn')
    and vr.created_at < now() - interval '7 days'
  union all
  select 'abwesenheit_unplausibel','mittel', e.id, trim(coalesce(e.first_name,'')||' '||coalesce(e.last_name,'')),
         'Abwesenheit: Ende vor Beginn', (a->>'from')||' bis '||(a->>'to')
  from public.employees e, jsonb_array_elements(coalesce(e.absences,'[]'::jsonb)) a
  where (a->>'from') is not null and (a->>'to') is not null and (a->>'from') > (a->>'to')
  union all
  select 'portalzugang_fehlt','niedrig', e.id, trim(coalesce(e.first_name,'')||' '||coalesce(e.last_name,'')),
         'Kein aktiver Portalzugang', coalesce(e.position,'')
  from public.employees e
  where e.status in ('active','training') and not exists (
    select 1 from public.app_users au where au.employee_id = e.id and au.active)
  union all
  -- NEU: Bewerber in einer Mitarbeiter-Phase, aber (noch) kein Mitarbeiter-Datensatz — Übernahme steckengeblieben.
  select 'bewerber_ohne_ma_datensatz','hoch', c.id, trim(coalesce(c.first_name,'')||' '||coalesce(c.last_name,'')),
         'In Mitarbeiter-Phase, aber kein Mitarbeiter-Datensatz',
         'Status „'||c.status||'" — Übernahme steckengeblieben, fehlt im Team-Bereich'
  from public.cvs c
  where c.status = any(emp_status);
end $function$;
