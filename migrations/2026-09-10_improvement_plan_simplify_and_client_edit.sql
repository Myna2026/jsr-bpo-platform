-- Arbeitsplan: (1) Fortschritt vereinfachen auf 3 Zustände (offen/in_arbeit/erledigt) — pausiert/wartet fallen weg.
-- (2) Condor darf aktiv mitarbeiten: Punkte anlegen (schon möglich) + anpassen (Titel/Priorität/Termine) + Zustand
--     setzen. AUSNAHME: unsere Maßnahmen (measures) und die Herkunft bleiben geschützt (nur Team ändert sie).

-- ── (1) 3 Zustände ───────────────────────────────────────────────────────────
alter table public.improvement_items drop constraint if exists improvement_items_status_check;
update public.improvement_items set status='in_arbeit' where status in ('pausiert','wartet');
update public.improvement_items set progress = case status when 'erledigt' then 100 when 'in_arbeit' then 50 else 0 end;
alter table public.improvement_items
  add constraint improvement_items_status_check check (status in ('offen','in_arbeit','erledigt'));

-- ── (2) Kunde darf Punkte ändern (nicht nur Team) ────────────────────────────
drop policy if exists imp_items_update_client on public.improvement_items;
create policy imp_items_update_client on public.improvement_items for update to authenticated
  using  (public.get_my_client_project_id() is not null and project_id = public.get_my_client_project_id())
  with check (public.get_my_client_project_id() is not null and project_id = public.get_my_client_project_id());

-- Schutz: bei Kunden-Updates bleiben measures + Herkunft unangetastet (unsere Maßnahmen gehören uns).
-- Greift NUR für Kunden-Aufrufer (get_my_client_project_id() gesetzt); Team-Updates laufen unverändert durch.
create or replace function public.imp_items_client_guard() returns trigger language plpgsql
  security definer set search_path=public as $$
begin
  if public.get_my_client_project_id() is not null then
    new.measures        := old.measures;
    new.origin          := old.origin;
    new.created_by       := old.created_by;
    new.created_by_name  := old.created_by_name;
    new.project_id       := old.project_id;
  end if;
  return new;
end$$;
drop trigger if exists imp_items_client_guard_trg on public.improvement_items;
create trigger imp_items_client_guard_trg before update on public.improvement_items
  for each row execute function public.imp_items_client_guard();
