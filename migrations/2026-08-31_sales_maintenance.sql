-- Sales-Akquise, Schnitt 5: Tot-Erkennung. Leads in contacted/opened, die 30 Tage keine Reaktion zeigten (keine
-- Antwort, kein Öffnen-Fortschritt), werden 'dead'. Läuft täglich per pg_cron. (Nachfass-Fälligkeit = next_followup_at
-- <= now, wird im Frontend gefiltert; Nachfassen bleibt manuell = getemplate, kein Auto-Außenversand.)
create or replace function public.sales_mark_dead()
returns integer language plpgsql security definer set search_path=public as $$
declare n int;
begin
  with upd as (
    update public.sales_leads set status='dead', updated_at=now()
    where status in ('contacted','opened')
      and coalesce(last_activity_at, created_at) < now() - interval '30 days'
    returning id
  )
  insert into public.sales_events(lead_id, kind, detail)
  select id, 'note', jsonb_build_object('auto','tot: 30 Tage ohne Reaktion') from upd;
  get diagnostics n = row_count;
  return n;
end $$;

do $$ begin
  perform 1 from cron.job where jobname='sales-mark-dead';
  if not found then perform cron.schedule('sales-mark-dead','0 6 * * *','select public.sales_mark_dead()'); end if;
exception when others then null;  -- pg_cron evtl. nicht verfügbar; Funktion bleibt manuell aufrufbar
end $$;
