-- Management-Calls Umbau R1: Der Freitext ist die einzige Eingabe, die KI leitet alles ab.
-- Additiv, kein Datenverlust. status bleibt text ohne CHECK -> 'partial' ist ohne Constraint erlaubt.

-- Zusammenfassung je Call (von der KI erzeugt).
alter table public.mgmt_calls add column if not exists summary text;

-- Punkte: Teilfortschritt + Zahlen-Erkennung ("10 geplant, 6 geschafft -> 4 offen") + Herkunftskette (Wiedervorlage).
alter table public.mgmt_call_items add column if not exists target_n     numeric;   -- geplant (Zahl), optional
alter table public.mgmt_call_items add column if not exists actual_n     numeric;   -- geschafft (Zahl), optional
alter table public.mgmt_call_items add column if not exists progress_note text;     -- "wie weit", wenn keine Zahl
alter table public.mgmt_call_items add column if not exists carried_from_item_id uuid
  references public.mgmt_call_items(id) on delete set null;                          -- der Punkt, aus dem dieser kopiert wurde
-- status: 'open' | 'done' | 'partial' (kein CHECK vorhanden -> additiv ok)

create index if not exists mgmt_call_items_carried_item_idx on public.mgmt_call_items(carried_from_item_id);
