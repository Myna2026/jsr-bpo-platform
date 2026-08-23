-- QM-Pflege als eigene wiederkehrende Aufgabe. Befund: QM (kpi_..QM, unit %, Handpflege) wurde bis KW32 gepflegt
-- und dann vergessen -> KW33/34 fehlen. QM war bisher nur implizit unter pl_kpi ("Kennzahlen des Projekts pflegen")
-- gebuendelt und darum unsichtbar. Eigene Aufgabe macht sie un-vergessbar (Cockpit-Zaehler + Slack-Reminder).
-- Owner projektleiter (verantwortet die Projektqualitaet, wie pl_kpi/pl_perf/pl_bericht), woechentlich, view performance.
insert into public.task_catalog(key,seq,owner,title,descr,view_key,count_key,cadence,window_weeks,auto_key,nav) values
 ('pl_qm', 265, array['projektleiter']::text[], 'QM-Bewertung pflegen',
  'Die woechentliche QM-Bewertung je Agent eintragen (Qualitaetsscore). Wird von Hand gepflegt, faellt sonst durch.',
  'performance', null, 'weekly', null, null, null)
on conflict (key) do update set seq=excluded.seq, owner=excluded.owner, title=excluded.title, descr=excluded.descr,
  view_key=excluded.view_key, count_key=excluded.count_key, cadence=excluded.cadence, window_weeks=excluded.window_weeks,
  auto_key=excluded.auto_key, nav=excluded.nav, updated_at=now();
