-- Clara-Automatik Schnitt 3: Besitz + Übergabe. Grundprinzip: ein Bewerber gehört immer genau EINEM —
-- Clara (Automatik arbeitet) ODER Deonita (Übergabe). Eine OFFENE Übergabe (resolved_at IS NULL) = "gehört
-- Deonita, wartet auf sie". Keine offene Übergabe + aktive Phase im Fenster = "gehört Clara". So kann niemand
-- angerufen werden, während Claras Mail/Fenster läuft. Clara sortiert NIE selbst aus — sie übergibt nur.

create table if not exists public.clara_handovers (
  id          uuid primary key default gen_random_uuid(),
  cv_id       uuid not null references public.cvs(id) on delete cascade,
  reason      text not null,          -- no_email | no_completion | no_booking | hard_cap
  phase       text,                   -- phase1 | phase2
  created_at  timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid,
  note        text
);
-- Nur EINE offene Übergabe je Bewerber (Exklusivität).
create unique index if not exists clara_handovers_one_open on public.clara_handovers(cv_id) where resolved_at is null;
create index if not exists clara_handovers_open_idx on public.clara_handovers(resolved_at) where resolved_at is null;

alter table public.clara_handovers enable row level security;
drop policy if exists clara_handovers_sel on public.clara_handovers;
create policy clara_handovers_sel on public.clara_handovers for select using (is_management() or is_hr());
drop policy if exists clara_handovers_upd on public.clara_handovers;
create policy clara_handovers_upd on public.clara_handovers for update using (is_management() or is_hr()) with check (is_management() or is_hr());

-- Werktage seit einem Zeitpunkt (Mo-Fr, Europe/Berlin), gezählt ab dem Tag NACH dem Ereignis bis heute.
-- NULL -> sehr groß (damit "nie passiert" nie fälschlich als frisch gilt).
create or replace function public.clara_workdays_since(p_ts timestamptz)
returns int language sql stable set search_path to 'public' as $$
  select case when p_ts is null then 9999 else (
    select count(*)::int from generate_series(
      ((p_ts at time zone 'Europe/Berlin')::date + 1),
      ((now() at time zone 'Europe/Berlin')::date),
      interval '1 day') d
    where extract(isodow from d) between 1 and 5
  ) end;
$$;

-- Bewertungs-Automat: legt fällige Übergaben an und löst hinfällige auf. Nur für AKTIVIERTE Phasen
-- (Clara aus -> manueller Prozess unberührt). Wird vom Cron aufgerufen (Schnitt 6). SECURITY DEFINER.
create or replace function public.clara_handover_scan()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  cfg jsonb; hand int; hcap int; p1 boolean; p2 boolean;
  v_new int := 0; v_res int := 0; r record;
begin
  select value into cfg from app_config where key='jsr_clara_auto_v1';
  if cfg is null then return jsonb_build_object('ok',false,'msg','keine Config'); end if;
  hand := coalesce((cfg->'windows'->>'handover_workdays')::int, 3);
  hcap := coalesce((cfg->'windows'->>'hard_cap_workdays')::int, 5);
  p1 := coalesce((cfg->'phases'->'phase1'->>'enabled')::boolean, false);
  p2 := coalesce((cfg->'phases'->'phase2'->>'enabled')::boolean, false);

  -- Auto-Resolve: Bewerber hat die Phase verlassen (weiter/abgelehnt/übernommen) ODER reagiert.
  update public.clara_handovers h set resolved_at=now()
   where h.resolved_at is null and (
     not exists (select 1 from public.cvs c where c.id=h.cv_id and c.status in ('cv_inbound','cv_confirmed'))
     or (h.phase='phase1' and exists (select 1 from public.cv_enrich_invites e where e.cv_id=h.cv_id and e.used_at is not null))
     or (h.phase='phase2' and exists (select 1 from public.interview_invites i where i.cv_id=h.cv_id and i.status='booked'))
   );
  get diagnostics v_res = row_count;

  for r in select c.id, c.status, c.email, c.status_changed_at, c.created_at
             from public.cvs c where c.status in ('cv_inbound','cv_confirmed') loop
    if (r.status='cv_inbound' and not p1) or (r.status='cv_confirmed' and not p2) then continue; end if;
    if exists (select 1 from public.clara_handovers h where h.cv_id=r.id and h.resolved_at is null) then continue; end if;
    declare
      v_reason text := null;
      v_phase text := case when r.status='cv_inbound' then 'phase1' else 'phase2' end;
    begin
      if nullif(btrim(coalesce(r.email,'')),'') is null then
        v_reason := 'no_email';
      elsif r.status='cv_inbound' then
        if exists (select 1 from public.cv_enrich_invites e where e.cv_id=r.id and e.used_at is null and clara_workdays_since(e.created_at) >= hand) then v_reason := 'no_completion'; end if;
      elsif r.status='cv_confirmed' then
        if exists (select 1 from public.interview_invites i where i.cv_id=r.id and i.status<>'booked' and clara_workdays_since(i.created_at) >= hand) then v_reason := 'no_booking'; end if;
      end if;
      if v_reason is null and clara_workdays_since(coalesce(r.status_changed_at, r.created_at)) >= hcap then v_reason := 'hard_cap'; end if;
      if v_reason is not null then
        insert into public.clara_handovers(cv_id, reason, phase) values (r.id, v_reason, v_phase)
          on conflict (cv_id) where resolved_at is null do nothing;
        v_new := v_new + 1;
      end if;
    end;
  end loop;

  return jsonb_build_object('ok',true,'neu',v_new,'aufgeloest',v_res);
end $$;
grant execute on function public.clara_handover_scan() to service_role;
grant execute on function public.clara_workdays_since(timestamptz) to authenticated, service_role;
