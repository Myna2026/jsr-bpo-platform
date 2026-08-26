-- Lenas Chat-Überwachung, schaltbar. Sie meldet nur Beleidigungen/Beschimpfungen/Mobbing/Betrugsversuche
-- an Management+HR, sie sanktioniert nicht. Transparenz: wo aktiv, sieht der Mitarbeiter den Hinweis;
-- wo aus, kein Hinweis und keine Prüfung.
--
-- Schaltbar auf drei Ebenen (app_config jsr_chat_monitoring_v1):
--   global=true            -> alle
--   projects=[project_id]  -> alle mit diesem project_id
--   employees=[emp_id]     -> gezielt einzelne
-- Geprüft wird nach ABSENDER: eine Nachricht wird geprüft, wenn ihr Absender überwacht ist.

begin;

insert into public.app_config(key, value, updated_at)
select 'jsr_chat_monitoring_v1', '{"global":false,"projects":[],"employees":[]}'::jsonb, now()
where not exists (select 1 from public.app_config where key='jsr_chat_monitoring_v1');

-- Ist der Mitarbeiter p_emp aktuell überwacht? (global ODER sein Projekt ODER er selbst)
create or replace function public.chat_is_monitored(p_emp uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare cfg jsonb; proj text;
begin
  if p_emp is null then return false; end if;
  select value into cfg from public.app_config where key='jsr_chat_monitoring_v1';
  if cfg is null then return false; end if;
  if coalesce((cfg->>'global')::boolean, false) then return true; end if;
  select project_id::text into proj from public.employees where id = p_emp;
  if proj is not null and exists (select 1 from jsonb_array_elements_text(coalesce(cfg->'projects','[]'::jsonb)) x where x = proj) then
    return true;
  end if;
  if exists (select 1 from jsonb_array_elements_text(coalesce(cfg->'employees','[]'::jsonb)) x where x = p_emp::text) then
    return true;
  end if;
  return false;
end $$;
revoke all    on function public.chat_is_monitored(uuid) from public;
grant execute on function public.chat_is_monitored(uuid) to authenticated;

-- Wird MEIN Chat geprüft? (für den sichtbaren Hinweis im Mitarbeiterportal)
create or replace function public.chat_monitoring_status()
returns boolean language sql stable security definer set search_path = public as $$
  select public.chat_is_monitored(public.get_my_employee_id());
$$;
grant execute on function public.chat_monitoring_status() to authenticated;

-- Gemeldete Verstöße. Nur Management+HR lesen/erledigen; Insert nur die Edge Function (service role).
create table if not exists public.chat_flags (
  id          uuid primary key default gen_random_uuid(),
  message_id  uuid unique references public.dm_messages(id) on delete cascade,
  thread_id   uuid,
  from_emp_id uuid,
  from_name   text,
  category    text,                         -- beleidigung | beschimpfung | mobbing | betrug
  excerpt     text,
  sent_at     timestamptz,
  created_at  timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by text
);
create index if not exists idx_chat_flags_created on public.chat_flags(created_at desc);
alter table public.chat_flags enable row level security;
drop policy if exists chat_flags_sel on public.chat_flags;
drop policy if exists chat_flags_upd on public.chat_flags;
create policy chat_flags_sel on public.chat_flags for select to authenticated using (public.is_admin());
create policy chat_flags_upd on public.chat_flags for update to authenticated using (public.is_admin()) with check (public.is_admin());
grant select, update on public.chat_flags to authenticated;

commit;
