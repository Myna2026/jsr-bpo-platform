-- =============================================================================
-- Freigabeverfahren für Wissensänderungen (Partner-Register kb_facts)         2026-09-17
-- Kein bestehender Wert wird mehr direkt überschrieben. Änderung (X → Y) und Löschung werden als Vorschlag
-- in kb_fact_changes vorgemerkt; der Kunde (jeder Zugang seines Projekts) bestätigt oder lehnt im Kundenportal
-- ab. Erst dann gilt der neue Wert. Neuanlagen gehen sofort live, gekennzeichnet „von Condor noch nicht
-- bestätigt" (client_confirmed_at null), und stehen ebenfalls in der Liste zum Abnicken.
-- Unbestätigte Vorschläge bleiben offen (alter Wert gilt), altern sichtbar, keine automatische Übernahme,
-- kein Verfall (User-Entscheidung: bei Notfallnummern wäre beides gleich falsch).
-- Wege: kb_change_propose (wir) · kb_change_decide (Kunde) · kb_change_withdraw (wir). Trigger auf kb_facts
-- sperrt jeden Direktweg an der Freigabe vorbei.
-- =============================================================================

alter table public.kb_facts add column if not exists client_confirmed_at timestamptz;
-- Bestand = Ausgangsbasis, gilt als bestätigt.
update public.kb_facts set client_confirmed_at = coalesce(client_confirmed_at, created_at, now()) where client_confirmed_at is null;

create table if not exists public.kb_fact_changes (
  id               uuid primary key default gen_random_uuid(),
  project_id       text not null,
  fact_id          uuid references public.kb_facts(id) on delete cascade,
  change_kind      text not null check (change_kind in ('new','update','delete')),
  topic            text, zielgebiet text, label text,                  -- Anzeige-Snapshot
  old_value        text, new_value text,
  payload          jsonb,                                               -- update: alle neuen Felder
  source           text, source_document_id uuid references public.kb_documents(id) on delete set null,
  source_locator   text, note text,
  proposed_by      uuid, proposed_by_name text, proposed_at timestamptz not null default now(),
  status           text not null default 'open' check (status in ('open','approved','rejected','withdrawn')),
  decided_by       uuid, decided_by_name text, decided_at timestamptz, decision_note text,
  reminded_at      timestamptz, reminder_count int not null default 0, escalated_at timestamptz
);
create index if not exists kb_fact_changes_open_idx on public.kb_fact_changes(project_id, status) where status = 'open';
create unique index if not exists kb_fact_changes_one_open_per_fact on public.kb_fact_changes(fact_id) where status = 'open' and fact_id is not null;

alter table public.kb_fact_changes enable row level security;
drop policy if exists kb_fact_changes_sel_internal on public.kb_fact_changes;
create policy kb_fact_changes_sel_internal on public.kb_fact_changes for select to authenticated
  using (coalesce((perm(auth.uid(),'wissen')->>'visible')::boolean,false) and perm_proj_ok(auth.uid(),'wissen',project_id));
drop policy if exists kb_fact_changes_sel_client on public.kb_fact_changes;
create policy kb_fact_changes_sel_client on public.kb_fact_changes for select to authenticated
  using (public.get_my_client_project_id() is not null and project_id = public.get_my_client_project_id());
-- Schreiben nur über die Definer-RPCs (keine Insert/Update-Policy).

-- ── Wächter: keine Wertänderung / Löschung am bestätigten Bestand ohne Freigabe ──────────────────────────
create or replace function public.kb_facts_guard() returns trigger language plpgsql as $$
begin
  if current_setting('kb.apply_change', true) = '1' then return new; end if;
  if old.client_confirmed_at is null then return new; end if;   -- eigener, noch unbestätigter Eintrag: frei
  if new.value is distinct from old.value or new.label is distinct from old.label
     or new.topic is distinct from old.topic or new.zielgebiet is distinct from old.zielgebiet
     or new.qualifier is distinct from old.qualifier or new.valid_from is distinct from old.valid_from
     or new.valid_to is distinct from old.valid_to or new.info_type is distinct from old.info_type then
    raise exception 'Dieser Eintrag ist vom Partner bestätigt. Änderungen laufen über die Freigabe (kb_change_propose).' using errcode = 'P0001';
  end if;
  if old.status = 'active' and new.status is distinct from 'active' then
    raise exception 'Dieser Eintrag ist vom Partner bestätigt. Löschen läuft über die Freigabe (kb_change_propose, delete).' using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists kb_facts_guard_trg on public.kb_facts;
create trigger kb_facts_guard_trg before update on public.kb_facts for each row execute function public.kb_facts_guard();

-- ── Vorschlag (wir) ───────────────────────────────────────────────────────────────────────────────────────
create or replace function public.kb_change_propose(p_project text, p_kind text, p_fact uuid default null, p_new jsonb default '{}'::jsonb,
                                                    p_source_document uuid default null, p_locator text default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_name text; v_fact public.kb_facts; v_id uuid; v_change uuid;
begin
  if not (perm_mode(v_uid,'wissen') = 'edit' and perm_proj_ok(v_uid,'wissen',p_project)) then
    raise exception 'Keine Berechtigung für dieses Partner-Wissen.';
  end if;
  select full_name into v_name from app_users where user_id = v_uid;
  perform set_config('kb.apply_change','1',true);

  if p_kind = 'new' then
    insert into kb_facts(project_id, topic, zielgebiet, info_type, label, value, qualifier, source, source_document_id, source_locator, confidence, status, valid_from, valid_to, created_by, updated_by, client_confirmed_at)
    values (p_project, p_new->>'topic', nullif(p_new->>'zielgebiet',''), coalesce(p_new->>'info_type','text'), p_new->>'label', p_new->>'value',
            case when p_new ? 'qualifier' then p_new->'qualifier' else null end,
            coalesce(p_new->>'source', case when p_source_document is null then 'manual' else 'file' end), p_source_document, p_locator,
            coalesce(p_new->>'confidence','confirmed'), 'active', nullif(p_new->>'valid_from','')::date, nullif(p_new->>'valid_to','')::date, v_uid, v_uid, null)
    returning id into v_id;
    insert into kb_fact_changes(project_id, fact_id, change_kind, topic, zielgebiet, label, old_value, new_value, payload, source, source_document_id, source_locator, note, proposed_by, proposed_by_name)
    values (p_project, v_id, 'new', p_new->>'topic', nullif(p_new->>'zielgebiet',''), p_new->>'label', null, p_new->>'value', p_new,
            coalesce(p_new->>'source', case when p_source_document is null then 'manual' else 'file' end), p_source_document, p_locator, p_note, v_uid, v_name)
    returning id into v_change;
    return jsonb_build_object('ok', true, 'fact_id', v_id, 'change_id', v_change, 'applied', true);
  end if;

  select * into v_fact from kb_facts where id = p_fact and project_id = p_project;
  if v_fact.id is null then raise exception 'Eintrag nicht gefunden.'; end if;

  if p_kind = 'update' then
    if v_fact.client_confirmed_at is null then
      -- noch unbestätigter eigener Eintrag: direkt ändern, der offene „neu"-Vorschlag zeigt den aktuellen Wert
      update kb_facts set topic = coalesce(p_new->>'topic', topic), zielgebiet = case when p_new ? 'zielgebiet' then nullif(p_new->>'zielgebiet','') else zielgebiet end,
        info_type = coalesce(p_new->>'info_type', info_type), label = coalesce(p_new->>'label', label), value = coalesce(p_new->>'value', value),
        qualifier = case when p_new ? 'qualifier' then p_new->'qualifier' else qualifier end,
        valid_from = case when p_new ? 'valid_from' then nullif(p_new->>'valid_from','')::date else valid_from end,
        valid_to = case when p_new ? 'valid_to' then nullif(p_new->>'valid_to','')::date else valid_to end,
        updated_by = v_uid, updated_at = now() where id = p_fact;
      update kb_fact_changes set new_value = coalesce(p_new->>'value', new_value), label = coalesce(p_new->>'label', label), payload = coalesce(payload,'{}'::jsonb) || p_new
       where fact_id = p_fact and status = 'open';
      return jsonb_build_object('ok', true, 'fact_id', p_fact, 'applied', true);
    end if;
    update kb_fact_changes set status = 'withdrawn', decided_at = now(), decision_note = 'ersetzt durch neuen Vorschlag' where fact_id = p_fact and status = 'open';
    insert into kb_fact_changes(project_id, fact_id, change_kind, topic, zielgebiet, label, old_value, new_value, payload, source, source_document_id, source_locator, note, proposed_by, proposed_by_name)
    values (p_project, p_fact, 'update', v_fact.topic, v_fact.zielgebiet, coalesce(p_new->>'label', v_fact.label), v_fact.value, coalesce(p_new->>'value', v_fact.value), p_new,
            coalesce(p_new->>'source', case when p_source_document is null then 'manual' else 'file' end), p_source_document, p_locator, p_note, v_uid, v_name)
    returning id into v_change;
    return jsonb_build_object('ok', true, 'fact_id', p_fact, 'change_id', v_change, 'applied', false);
  end if;

  if p_kind = 'delete' then
    if v_fact.client_confirmed_at is null then
      update kb_facts set status = 'archived', updated_by = v_uid, updated_at = now() where id = p_fact;
      update kb_fact_changes set status = 'withdrawn', decided_at = now(), decision_note = 'von uns zurückgezogen' where fact_id = p_fact and status = 'open';
      return jsonb_build_object('ok', true, 'fact_id', p_fact, 'applied', true);
    end if;
    update kb_fact_changes set status = 'withdrawn', decided_at = now(), decision_note = 'ersetzt durch neuen Vorschlag' where fact_id = p_fact and status = 'open';
    insert into kb_fact_changes(project_id, fact_id, change_kind, topic, zielgebiet, label, old_value, new_value, source, note, proposed_by, proposed_by_name)
    values (p_project, p_fact, 'delete', v_fact.topic, v_fact.zielgebiet, v_fact.label, v_fact.value, null, 'manual', p_note, v_uid, v_name)
    returning id into v_change;
    return jsonb_build_object('ok', true, 'fact_id', p_fact, 'change_id', v_change, 'applied', false);
  end if;
  raise exception 'Unbekannte Änderungsart %', p_kind;
end $$;
revoke all on function public.kb_change_propose(text,text,uuid,jsonb,uuid,text,text) from public;
grant execute on function public.kb_change_propose(text,text,uuid,jsonb,uuid,text,text) to authenticated;

-- ── Entscheidung (Kunde: jeder Zugang des Projekts) ───────────────────────────────────────────────────────
create or replace function public.kb_change_decide(p_change uuid, p_decision text, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_ch public.kb_fact_changes; v_name text; v_p jsonb;
begin
  select * into v_ch from kb_fact_changes where id = p_change;
  if v_ch.id is null then raise exception 'Vorschlag nicht gefunden.'; end if;
  if public.get_my_client_project_id() is null or public.get_my_client_project_id() <> v_ch.project_id then
    raise exception 'Nur der Partner dieses Projekts entscheidet über seine Wissensänderungen.';
  end if;
  if v_ch.status <> 'open' then raise exception 'Dieser Vorschlag ist bereits entschieden (%).', v_ch.status; end if;
  if p_decision not in ('approve','reject') then raise exception 'Entscheidung muss approve oder reject sein.'; end if;
  select coalesce(u.full_name, c.company_name) into v_name from app_users u left join client_accounts c on c.id = u.client_id where u.user_id = v_uid;
  perform set_config('kb.apply_change','1',true);
  if p_decision = 'approve' then
    if v_ch.change_kind = 'update' then
      v_p := coalesce(v_ch.payload, '{}'::jsonb);
      update kb_facts set topic = coalesce(v_p->>'topic', topic), zielgebiet = case when v_p ? 'zielgebiet' then nullif(v_p->>'zielgebiet','') else zielgebiet end,
        info_type = coalesce(v_p->>'info_type', info_type), label = coalesce(v_p->>'label', label), value = coalesce(v_ch.new_value, value),
        qualifier = case when v_p ? 'qualifier' then v_p->'qualifier' else qualifier end,
        valid_from = case when v_p ? 'valid_from' then nullif(v_p->>'valid_from','')::date else valid_from end,
        valid_to = case when v_p ? 'valid_to' then nullif(v_p->>'valid_to','')::date else valid_to end,
        source_document_id = coalesce(v_ch.source_document_id, source_document_id), source_locator = coalesce(v_ch.source_locator, source_locator),
        client_confirmed_at = now(), updated_at = now() where id = v_ch.fact_id;
    elsif v_ch.change_kind = 'delete' then
      update kb_facts set status = 'archived', updated_at = now() where id = v_ch.fact_id;
    elsif v_ch.change_kind = 'new' then
      update kb_facts set client_confirmed_at = now(), updated_at = now() where id = v_ch.fact_id;
    end if;
  else
    if v_ch.change_kind = 'new' then
      update kb_facts set status = 'archived', updated_at = now() where id = v_ch.fact_id;   -- abgelehnte Neuanlage verschwindet
    end if;
  end if;
  update kb_fact_changes set status = case when p_decision = 'approve' then 'approved' else 'rejected' end,
    decided_by = v_uid, decided_by_name = v_name, decided_at = now(), decision_note = nullif(p_note,'') where id = p_change;
  return jsonb_build_object('ok', true, 'status', case when p_decision = 'approve' then 'approved' else 'rejected' end);
end $$;
revoke all on function public.kb_change_decide(uuid,text,text) from public;
grant execute on function public.kb_change_decide(uuid,text,text) to authenticated;

-- ── Zurückziehen (wir) ────────────────────────────────────────────────────────────────────────────────────
create or replace function public.kb_change_withdraw(p_change uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_ch public.kb_fact_changes;
begin
  select * into v_ch from kb_fact_changes where id = p_change;
  if v_ch.id is null then raise exception 'Vorschlag nicht gefunden.'; end if;
  if not (perm_mode(v_uid,'wissen') = 'edit' and perm_proj_ok(v_uid,'wissen',v_ch.project_id)) then raise exception 'Keine Berechtigung.'; end if;
  if v_ch.status <> 'open' then raise exception 'Dieser Vorschlag ist bereits entschieden (%).', v_ch.status; end if;
  perform set_config('kb.apply_change','1',true);
  if v_ch.change_kind = 'new' then update kb_facts set status = 'archived', updated_at = now() where id = v_ch.fact_id; end if;
  update kb_fact_changes set status = 'withdrawn', decided_by = v_uid, decided_at = now(), decision_note = 'von uns zurückgezogen' where id = p_change;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.kb_change_withdraw(uuid) from public;
grant execute on function public.kb_change_withdraw(uuid) to authenticated;
