-- Clara-Automatik Schnitt 5: Absagen mit 48-h-Verzögerung + Kontrollliste.
-- Grund: eine Absage in derselben Sekunde wirkt maschinell. Beim Statuswechsel wird die Absage EINGEPLANT
-- (fällig in reject_delay_hours), der Versand (Mailer/Cron) prüft bei Fälligkeit erneut den Status — hat HR
-- revidiert, geht nichts raus. Nur rejected_by_us / rejected_by_client / no_contact. Nie rejected_by_employee
-- (Bewerber zieht selbst zurück) und nie blacklist.

create table if not exists public.clara_rejections (
  id            uuid primary key default gen_random_uuid(),
  cv_id         uuid not null references public.cvs(id) on delete cascade,
  reject_status text not null,
  scheduled_at  timestamptz not null default now(),
  due_at        timestamptz not null,
  sent_at       timestamptz,
  cancelled_at  timestamptz,
  cancel_reason text,
  message_id    text,
  error         text
);
create index if not exists clara_rejections_due_idx on public.clara_rejections(due_at) where sent_at is null and cancelled_at is null;
create index if not exists clara_rejections_cv_idx on public.clara_rejections(cv_id);

alter table public.clara_rejections enable row level security;
drop policy if exists clara_rej_sel on public.clara_rejections;
create policy clara_rej_sel on public.clara_rejections for select using (is_management() or is_hr());
drop policy if exists clara_rej_upd on public.clara_rejections;
create policy clara_rej_upd on public.clara_rejections for update using (is_management() or is_hr()) with check (is_management() or is_hr());

-- Trigger: beim Wechsel in einen der drei Ausgänge eine Absage EINPLANEN (nur wenn Automatik für den Ausgang an,
-- keine offene Absage schon vorhanden). Fängt jeden Weg ab (Kanban, Modal, Status-Picker). Clara entscheidet
-- NICHTS selbst — HR setzt den Status, Clara verschickt nur zeitversetzt.
create or replace function public.clara_schedule_rejection()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare cfg jsonb; delay int;
begin
  if NEW.status is not distinct from OLD.status then return NEW; end if;
  if NEW.status not in ('rejected_by_us','rejected_by_client','no_contact') then return NEW; end if;
  select value into cfg from app_config where key='jsr_clara_auto_v1';
  if not coalesce((cfg->'rejects'->NEW.status->>'enabled')::boolean, false) then return NEW; end if;
  if exists (select 1 from public.clara_rejections r where r.cv_id=NEW.id and r.sent_at is null and r.cancelled_at is null) then return NEW; end if;
  delay := coalesce((cfg->>'reject_delay_hours')::int, 48);
  insert into public.clara_rejections(cv_id, reject_status, due_at)
    values (NEW.id, NEW.status, now() + make_interval(hours => delay));
  return NEW;
end $$;
drop trigger if exists clara_schedule_rejection_trg on public.cvs;
create trigger clara_schedule_rejection_trg after update of status on public.cvs
  for each row execute function public.clara_schedule_rejection();
