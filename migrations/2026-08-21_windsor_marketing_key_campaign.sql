-- windsor_marketing: Unique-Key um campaign erweitern (mehrere Meta-Kampagnen je Tag ab 20.08.).
-- Der 2-spaltige Key (datasource,date) liess nur EINE Zeile/Tag zu -> fb-Insert brach ab (3 parallele Kampagnen).
-- NULLS NOT DISTINCT (PG15+): behandelt NULL-campaign (Instagram organisch) als GLEICH -> genau eine ig-Zeile/Tag,
-- und Windsors Upsert ON CONFLICT (datasource,date,campaign) trifft die bestehende NULL-Zeile (sonst wuerde ig
-- bei jedem Lauf duplizieren, weil NULL sonst als verschieden gilt).
alter table public.windsor_marketing drop constraint if exists windsor_marketing_datasource_date_key;
alter table public.windsor_marketing
  add constraint windsor_marketing_dsc_key unique nulls not distinct (datasource, date, campaign);
