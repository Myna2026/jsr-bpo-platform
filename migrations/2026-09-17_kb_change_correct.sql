-- Freigabe: (1) Erinnerungsmails/Eskalation wieder raus (Cron kb-change-remind entfernt, Funktion gelöscht; der Tab im
-- Kundenportal reicht). (2) Dritte Möglichkeit: der Kunde korrigiert den Wert direkt und bestätigt; dann gilt SEIN Wert.
select cron.unschedule('kb-change-remind') where exists (select 1 from cron.job where jobname='kb-change-remind');
alter table public.kb_fact_changes add column if not exists decided_value text;   -- vom Kunden korrigierter Wert (falls abweichend)

create or replace function public.kb_change_decide(p_change uuid, p_decision text, p_note text default null, p_value text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_ch public.kb_fact_changes; v_name text; v_p jsonb; v_val text; v_corrected boolean := false;
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
    -- Korrektur: Kunde tippt den richtigen Wert ein → der gilt (auch bei Löschvorschlag: Eintrag bleibt mit dem korrigierten Wert).
    v_val := nullif(btrim(coalesce(p_value,'')),'');
    v_corrected := v_val is not null and v_val is distinct from v_ch.new_value;
    if v_ch.change_kind = 'update' or (v_ch.change_kind = 'delete' and v_corrected) then
      v_p := coalesce(v_ch.payload, '{}'::jsonb);
      update kb_facts set topic = coalesce(v_p->>'topic', topic), zielgebiet = case when v_p ? 'zielgebiet' then nullif(v_p->>'zielgebiet','') else zielgebiet end,
        info_type = coalesce(v_p->>'info_type', info_type), label = coalesce(v_p->>'label', label),
        value = coalesce(v_val, v_ch.new_value, value),
        qualifier = case when v_p ? 'qualifier' then v_p->'qualifier' else qualifier end,
        valid_from = case when v_p ? 'valid_from' then nullif(v_p->>'valid_from','')::date else valid_from end,
        valid_to = case when v_p ? 'valid_to' then nullif(v_p->>'valid_to','')::date else valid_to end,
        source_document_id = coalesce(v_ch.source_document_id, source_document_id), source_locator = coalesce(v_ch.source_locator, source_locator),
        client_confirmed_at = now(), updated_at = now() where id = v_ch.fact_id;
    elsif v_ch.change_kind = 'delete' then
      update kb_facts set status = 'archived', updated_at = now() where id = v_ch.fact_id;
    elsif v_ch.change_kind = 'new' then
      update kb_facts set value = coalesce(v_val, value), client_confirmed_at = now(), updated_at = now() where id = v_ch.fact_id;
    end if;
  else
    if v_ch.change_kind = 'new' then
      update kb_facts set status = 'archived', updated_at = now() where id = v_ch.fact_id;   -- abgelehnte Neuanlage verschwindet
    end if;
  end if;
  update kb_fact_changes set status = case when p_decision = 'approve' then 'approved' else 'rejected' end,
    decided_value = case when p_decision = 'approve' and v_corrected then v_val else null end,
    decided_by = v_uid, decided_by_name = v_name, decided_at = now(), decision_note = nullif(p_note,'') where id = p_change;
  return jsonb_build_object('ok', true, 'status', case when p_decision = 'approve' then 'approved' else 'rejected' end, 'corrected', v_corrected);
end $$;
revoke all on function public.kb_change_decide(uuid,text,text,text) from public;
grant execute on function public.kb_change_decide(uuid,text,text,text) to authenticated;
drop function if exists public.kb_change_decide(uuid,text,text);
