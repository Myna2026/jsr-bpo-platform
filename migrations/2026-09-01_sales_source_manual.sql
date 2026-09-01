-- Herkunft: 'manual' (manuell angelegt) als vierte erlaubte Quelle zulassen. Versteckte zweite Allow-Liste
-- (CHECK-Constraint) muss mit der fachlichen Quelle-Liste mitgezogen werden, sonst still abgelehnt.
alter table public.sales_leads drop constraint if exists sales_leads_source_check;
alter table public.sales_leads add constraint sales_leads_source_check
  check (source = any (array['mail'::text,'list'::text,'apollo'::text,'manual'::text]));
