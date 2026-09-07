-- Management-Calls: Aufgaben-Postausgang. Die EINZIGE Brücke aus der abgeschotteten Notiz-Welt.
-- Nur die einzelne Aufgabe geht raus (Text/Kontext/Frist) — nie das Protokoll, nie die anderen Punkte,
-- nie wer sonst was macht. Rückkanal ist allein das Erledigt-Signal (Trigger).

create table if not exists public.mgmt_task_out (
  id              uuid primary key default gen_random_uuid(),
  item_id         uuid references public.mgmt_call_items(id) on delete set null,  -- Rückverknüpfung; für den Empfänger eine opake ID (mgmt_call_items ist für ihn gesperrt)
  assignee_user   uuid not null,                 -- app_users.user_id / auth.uid() des Empfängers
  text            text not null,                 -- die Aufgabe, bewusst neutral formuliert (kein Herkunftshinweis)
  context         text,                          -- optionaler Zusatz, "so weit nötig"
  due_date        date,
  status          text not null default 'open',  -- open | done
  done_at         timestamptz,
  done_by         uuid,
  created_by      uuid,
  created_by_name text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists mgmt_task_out_assignee_open_idx on public.mgmt_task_out(assignee_user) where status='open';
create index if not exists mgmt_task_out_item_idx on public.mgmt_task_out(item_id);

-- ── RLS: zwei Welten ─────────────────────────────────────────────────────────
alter table public.mgmt_task_out enable row level security;
drop policy if exists mgmt_task_out_mgmt on public.mgmt_task_out;
drop policy if exists mgmt_task_out_assignee_sel on public.mgmt_task_out;
drop policy if exists mgmt_task_out_assignee_upd on public.mgmt_task_out;
-- Die Vier: alles (zuweisen, verwalten, Status sehen).
create policy mgmt_task_out_mgmt on public.mgmt_task_out for all to authenticated
  using (public.is_mgmt_call_user()) with check (public.is_mgmt_call_user());
-- Empfänger: nur die EIGENEN Zeilen lesen …
create policy mgmt_task_out_assignee_sel on public.mgmt_task_out for select to authenticated
  using (assignee_user = auth.uid());
-- … und nur die eigene Zeile ändern (Spalten-Schutz per Trigger unten: nur Status).
create policy mgmt_task_out_assignee_upd on public.mgmt_task_out for update to authenticated
  using (assignee_user = auth.uid()) with check (assignee_user = auth.uid());
grant select, insert, update, delete on public.mgmt_task_out to authenticated;

-- ── Trigger 1: Spalten-Schutz. Ein Empfänger darf NUR den Status setzen. ──────
-- Text/Kontext/Frist/Verknüpfung/Empfänger bleiben unveränderlich für Nicht-Freigabeliste.
create or replace function public.mgmt_task_out_guard()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if not public.is_mgmt_call_user() then
    new.text          := old.text;
    new.context       := old.context;
    new.due_date      := old.due_date;
    new.item_id       := old.item_id;
    new.assignee_user := old.assignee_user;
    new.created_by    := old.created_by;
    new.created_by_name := old.created_by_name;
    new.created_at    := old.created_at;
  end if;
  -- Erledigt-Stempel automatisch führen.
  if new.status = 'done' and coalesce(old.status,'') <> 'done' then
    new.done_at := now(); new.done_by := auth.uid();
  elsif new.status <> 'done' then
    new.done_at := null; new.done_by := null;
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists mgmt_task_out_guard_t on public.mgmt_task_out;
create trigger mgmt_task_out_guard_t before update on public.mgmt_task_out
  for each row execute function public.mgmt_task_out_guard();

-- ── Trigger 2: Erledigt-Signal zurück in die Notiz-Welt (Einbahn). ────────────
-- Wird die Aufgabe erledigt, gilt der verknüpfte Punkt als erledigt (SECURITY DEFINER umgeht die RLS,
-- der Empfänger schreibt mgmt_call_items NIE selbst). Reopen setzt den Punkt zurück auf offen.
create or replace function public.mgmt_task_out_sync()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.item_id is null then return new; end if;
  if new.status = 'done' and coalesce(old.status,'') <> 'done' then
    update public.mgmt_call_items set status='done', done_at=now(), updated_at=now() where id=new.item_id;
  elsif new.status <> 'done' and old.status = 'done' then
    update public.mgmt_call_items set status='open', done_at=null, updated_at=now() where id=new.item_id and status='done';
  end if;
  return new;
end $$;
drop trigger if exists mgmt_task_out_sync_t on public.mgmt_task_out;
create trigger mgmt_task_out_sync_t after update on public.mgmt_task_out
  for each row execute function public.mgmt_task_out_sync();
