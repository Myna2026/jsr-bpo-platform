-- Funktionen zu den Coach-Frage-Vorschlaegen. Schreiben auf coach_questions laeuft
-- ausschliesslich hierueber; der Kundenzugang hat auf beide Tabellen kein Schreibrecht.

-- Wer darf vorschlagen: der Auftraggeber fuer sein Projekt, oder wir mit Wissens-Schreibrecht.
create or replace function public.coach_darf_vorschlagen(p_project text) returns boolean
language sql stable security definer set search_path to 'public' as $$
  select (get_my_client_project_id() is not null and get_my_client_project_id() = p_project)
      or (perm_mode(auth.uid(),'wissen') = 'edit' and perm_proj_ok(auth.uid(),'wissen',p_project));
$$;

-- ── Bewerten: steht sofort, keine Freigabe ────────────────────────────────────────────────
create or replace function public.coach_question_rate(p_question uuid, p_stars int, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid(); v_name text; v_proj text;
begin
  select project_id into v_proj from coach_questions where id = p_question;
  if v_proj is null then raise exception 'Frage nicht gefunden.'; end if;
  if not coach_darf_vorschlagen(v_proj) then raise exception 'Keine Berechtigung fuer dieses Projekt.'; end if;
  if p_stars is not null and (p_stars < 1 or p_stars > 5) then raise exception 'Bewertung muss zwischen 1 und 5 liegen.'; end if;
  select full_name into v_name from app_users where user_id = v_uid;
  update coach_questions
     set client_quality = p_stars, client_quality_note = nullif(btrim(coalesce(p_note,'')),''),
         client_quality_at = now(), client_quality_by = v_uid, client_quality_by_name = v_name
   where id = p_question;
  return jsonb_build_object('ok', true);
end; $$;

-- ── Vorschlagen: aendern, neu, ablehnen ───────────────────────────────────────────────────
create or replace function public.coach_change_propose(
  p_project text, p_kind text, p_question uuid default null,
  p_new jsonb default '{}'::jsonb, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid(); v_name text; v_q coach_questions; v_id uuid; v_alt jsonb;
begin
  if not coach_darf_vorschlagen(p_project) then raise exception 'Keine Berechtigung fuer dieses Projekt.'; end if;
  if p_kind not in ('edit','new','reject') then raise exception 'Unbekannte Vorschlagsart.'; end if;
  select full_name into v_name from app_users where user_id = v_uid;

  if p_kind in ('edit','reject') then
    select * into v_q from coach_questions where id = p_question;
    if v_q.id is null then raise exception 'Frage nicht gefunden.'; end if;
    if v_q.project_id <> p_project then raise exception 'Frage gehoert zu einem anderen Projekt.'; end if;
    -- Nur ein offener Vorschlag je Frage: sonst widersprechen sich zwei Aenderungen still.
    if exists (select 1 from coach_question_changes where question_id = p_question and status = 'open') then
      raise exception 'Zu dieser Frage liegt bereits ein offener Vorschlag vor.';
    end if;
    v_alt := jsonb_build_object('kind',v_q.kind,'topic',v_q.topic,'zielgebiet',v_q.zielgebiet,
      'difficulty',v_q.difficulty,'prompt',v_q.prompt,'options',v_q.options,'answer',v_q.answer,
      'explanation',v_q.explanation,'status',v_q.status);
  end if;
  -- Eine Ablehnung ohne Begruendung waere wertlos: in drei Monaten weiss niemand mehr, warum.
  if p_kind = 'reject' and btrim(coalesce(p_note,'')) = '' then
    raise exception 'Fuer eine Ablehnung ist eine Begruendung noetig.';
  end if;
  if p_kind in ('edit','new') and btrim(coalesce(p_new->>'prompt','')) = '' then
    raise exception 'Die Frage darf nicht leer sein.';
  end if;

  insert into coach_question_changes(project_id, question_id, change_kind, old_value, new_value, note,
                                     proposed_by, proposed_by_name)
  values (p_project, p_question, p_kind, v_alt,
          case when p_kind = 'reject' then null else p_new end,
          nullif(btrim(coalesce(p_note,'')),''), v_uid, v_name)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end; $$;

-- ── Zurueckziehen, solange offen ──────────────────────────────────────────────────────────
create or replace function public.coach_change_withdraw(p_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_row coach_question_changes;
begin
  select * into v_row from coach_question_changes where id = p_id;
  if v_row.id is null then raise exception 'Vorschlag nicht gefunden.'; end if;
  if v_row.status <> 'open' then raise exception 'Der Vorschlag ist bereits entschieden.'; end if;
  if not (v_row.proposed_by = auth.uid() or coach_darf_vorschlagen(v_row.project_id)) then
    raise exception 'Keine Berechtigung.';
  end if;
  update coach_question_changes set status='withdrawn', decided_at=now() where id = p_id;
  return jsonb_build_object('ok', true);
end; $$;

-- ── Entscheiden: nur intern, mit Wissens-Schreibrecht auf dem Projekt ─────────────────────
create or replace function public.coach_change_decide(
  p_id uuid, p_status text, p_note text default null, p_value jsonb default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid(); v_name text; v_row coach_question_changes; v_neu jsonb; v_qid uuid;
begin
  select * into v_row from coach_question_changes where id = p_id;
  if v_row.id is null then raise exception 'Vorschlag nicht gefunden.'; end if;
  if v_row.status <> 'open' then raise exception 'Der Vorschlag ist bereits entschieden.'; end if;
  if not (perm_mode(v_uid,'wissen') = 'edit' and perm_proj_ok(v_uid,'wissen',v_row.project_id)) then
    raise exception 'Nur mit Schreibrecht auf dem Partner-Wissen dieses Projekts.';
  end if;
  if p_status not in ('approved','rejected') then raise exception 'Unbekannte Entscheidung.'; end if;
  select full_name into v_name from app_users where user_id = v_uid;
  -- p_value erlaubt, den Vorschlag vor der Freigabe noch zu korrigieren.
  v_neu := coalesce(p_value, v_row.new_value);

  if p_status = 'approved' then
    if v_row.change_kind = 'edit' then
      update coach_questions set
        prompt      = coalesce(v_neu->>'prompt', prompt),
        options     = coalesce(v_neu->'options', options),
        answer      = coalesce(v_neu->'answer', answer),
        explanation = coalesce(v_neu->>'explanation', explanation),
        topic       = coalesce(v_neu->>'topic', topic),
        zielgebiet  = coalesce(nullif(v_neu->>'zielgebiet',''), zielgebiet),
        difficulty  = coalesce(v_neu->>'difficulty', difficulty),
        updated_at  = now()
      where id = v_row.question_id;
      v_qid := v_row.question_id;
    elsif v_row.change_kind = 'reject' then
      update coach_questions set status='blocked', judge_note =
        coalesce(judge_note||' | ','')||'Vom Auftraggeber abgelehnt: '||coalesce(v_row.note,''), updated_at=now()
      where id = v_row.question_id;
      v_qid := v_row.question_id;
    else  -- new
      insert into coach_questions(project_id, kind, difficulty, topic, zielgebiet, prompt, options, answer,
                                  explanation, status, gen_by, source_kind, source_label)
      values (v_row.project_id, coalesce(v_neu->>'kind','free'), coalesce(v_neu->>'difficulty','mittel'),
              v_neu->>'topic', nullif(v_neu->>'zielgebiet',''), v_neu->>'prompt',
              case when v_neu ? 'options' then v_neu->'options' else null end,
              case when v_neu ? 'answer' then v_neu->'answer' else null end,
              v_neu->>'explanation', 'active', 'kunde', 'client', 'Vorschlag des Auftraggebers')
      returning id into v_qid;
    end if;
  end if;

  update coach_question_changes
     set status = p_status, decided_by = v_uid, decided_by_name = v_name, decided_at = now(),
         decision_note = nullif(btrim(coalesce(p_note,'')),''), applied_question_id = v_qid
   where id = p_id;
  return jsonb_build_object('ok', true, 'question_id', v_qid);
end; $$;

revoke all on function public.coach_change_decide(uuid,text,text,jsonb) from public;
grant execute on function public.coach_change_decide(uuid,text,text,jsonb) to authenticated;
grant execute on function public.coach_change_propose(text,text,uuid,jsonb,text) to authenticated;
grant execute on function public.coach_change_withdraw(uuid) to authenticated;
grant execute on function public.coach_question_rate(uuid,int,text) to authenticated;
