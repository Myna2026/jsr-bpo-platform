-- Datengetriebene Aufgaben: eine Aufgabenliste statt zwei. Die abgeleiteten Cockpit-Hinweise werden zu
-- echten Katalog-Aufgaben (Owner, Sperrbildschirm, Slack), erscheinen aber nur bei Bedarf und verschwinden,
-- wenn erledigt. (1) Flag am Katalog. (2) Flag fuer die Auffaelligkeiten. (3) Wechselkurs als neue Aufgabe.
-- (4) Geteilte Zaehler-Funktion task_open_counts() -- Frontend UND Edge Function task-reminders lesen dieselbe
-- Wahrheit (kein doppelter Zaehler-Code). Additiv.

-- (1) Flag: datengetrieben = Instanz nur sichtbar, solange der count_key > 0 ist (kein Haekchen noetig).
alter table public.task_catalog add column if not exists data_gated boolean not null default false;

-- (2) Die Auffaelligkeiten datengetrieben schalten (Rest bleibt feste Checkliste; im Editor pro Aufgabe umstellbar).
--     hr_cv_phase=cv_stuck, hr_vertraege=contract_gap, lead_vacreq=vacreq_open.
update public.task_catalog set data_gated=true, updated_at=now()
 where key in ('hr_cv_phase','hr_vertraege','lead_vacreq');

-- (3) Wechselkurs als echte Aufgabe (Owner Finance + Management), datengetrieben, faellig ab dem 15.
insert into public.task_catalog(key,seq,owner,title,descr,view_key,count_key,cadence,window_weeks,auto_key,nav,data_gated) values
 ('fin_fx', 215, array['finance','management']::text[], 'Wechselkurs eintragen',
  'Den Monatskurs fuer den Folgemonat eintragen, sobald er feststeht (faellig ab dem 15.). Ohne Kurs koennen Gehaelter in Fremdwaehrung nicht in EUR gerechnet werden.',
  'superadmin', 'fx_missing', null, null, null, '{"sysSection":"fx_rates"}'::jsonb, true)
on conflict (key) do update set seq=excluded.seq, owner=excluded.owner, title=excluded.title, descr=excluded.descr,
  view_key=excluded.view_key, count_key=excluded.count_key, nav=excluded.nav, data_gated=excluded.data_gated, updated_at=now();

-- (4) Geteilte Zaehler-Funktion. Je datengetriebenem count_key die offene Menge; project_id NULL = global,
--     sonst je Projekt (Urlaubsantraege -> Lead sieht sein Projekt). Nur Zeilen mit n>0 -> fehlt der Schluessel,
--     ist die Aufgabe aus. SECURITY DEFINER, damit Owner-Rollen den globalen Zaehler sehen (Zaehler sind
--     nicht sensibel); RLS auf den Zieltabellen bleibt fuer die eigentlichen Daten unveraendert.
create or replace function public.task_open_counts()
returns table(count_key text, project_id text, n integer)
language sql stable security definer set search_path = public as $$
  -- CVs ohne Aktion: >7 Tage keine Statusaenderung, nicht aktiv, nicht abgelehnt (Spiegel von COCKPIT_FILTERS.cv_stuck)
  select 'cv_stuck'::text, null::text, count(*)::int
    from cvs
   where status is distinct from 'active'
     and status not in ('rejected_by_us','rejected_by_employee','rejected_by_client','no_contact','homeoffice_only','incomplete','blacklist')
     and coalesce(status_changed_at, cv_date::timestamptz) < now() - interval '7 days'
  having count(*) > 0
  union all
  -- Vertraege, die in <=30 Tagen auslaufen (Spiegel von counts.expiring)
  select 'contract_gap'::text, null::text, count(*)::int
    from employees
   where contract->>'end' ~ '^\d{4}-\d{2}-\d{2}'
     and (contract->>'end')::date >= current_date
     and (contract->>'end')::date <= current_date + 30
  having count(*) > 0
  union all
  -- Offene Urlaubsantraege je Projekt des Antragstellers
  select 'vacreq_open'::text, e.project_id::text, count(*)::int
    from vacation_requests vr
    join employees e on e.id = vr.employee_id
   where vr.status = 'pending'
   group by e.project_id
  union all
  -- Wechselkurs fuer den Folgemonat fehlt, faellig ab dem 15. (Spiegel von fxRateReminder)
  select 'fx_missing'::text, null::text, 1
   where extract(day from current_date) >= 15
     and coalesce(
       ((select value from app_config where key = 'jsr_fx_rates_v1')
         ->> to_char(date_trunc('month', current_date) + interval '1 month', 'YYYY-MM'))::numeric,
       0) <= 0;
$$;
grant execute on function public.task_open_counts() to authenticated;
