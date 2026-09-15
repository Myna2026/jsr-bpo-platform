-- =============================================================================
-- Telefonaktion-Werkzeug SCHNITT 2: Ergebnis-Knöpfe config-getrieben.
-- SICHERHEIT: die laufende Aktion bleibt auf dem ALTEN, fest verdrahteten Pfad.
--   phone_link_log verzweigt: config.engine='generic' → generischer Pfad (neue Kampagnen),
--   sonst → LEGACY (Wort für Wort das bisherige Verhalten). Die laufende Aktion hat KEIN
--   engine-Flag → Legacy → garantiert unverändert. Umstellen der laufenden Aktion auf
--   'generic' ist ein späterer, bewusster Schritt (nicht im Betrieb).
-- Frontend rendert die Knöpfe aus config.buttons (laufende Aktion: dieselben 3 → gleiche UI).
-- Idempotent.
-- =============================================================================

-- Config (+ Name) zum Token für die Seite (Knöpfe rendern). Anon.
create or replace function public.phone_link_config(p_token text)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('name', k.name, 'config', k.config)
  from public.call_campaigns k where k.public_token = p_token and k.active;
$$;
revoke all on function public.phone_link_config(text) from public;
grant execute on function public.phone_link_config(text) to anon, authenticated;

create or replace function public.phone_link_log(p_token text, p_assignee uuid, p_lead_id uuid, p_result text,
  p_reason text default null, p_date date default null, p_time text default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare k public.call_campaigns; l public.call_leads; c public.cvs; nm text; ev uuid; t_time time;
  b jsonb; eff jsonb; needs text; newstatus text; do_cal boolean; do_bump boolean; reason_ok boolean;
begin
  select * into k from public.call_campaigns where public_token = p_token and active;
  if not found then raise exception 'Ungültiger Link.'; end if;
  select * into l from public.call_leads where id = p_lead_id;
  if not found or l.campaign_id<>k.id or l.assignee_user_id<>p_assignee then raise exception 'Nicht berechtigt.'; end if;
  select * into c from public.cvs where id = l.cv_id;
  nm := l.assignee_name;
  t_time := case when p_time is null or btrim(p_time)='' then null else p_time::time end;

  -- Zurücksetzen ist in beiden Engines gleich.
  if p_result = 'open' then
    update public.call_leads set status='open', reject_reason=null, followup_date=null, appointment_date=null,
      appointment_time=null, note=null, calendar_event_id=null, updated_by=p_assignee, updated_at=now() where id=l.id;
    return jsonb_build_object('ok', true, 'result', 'open');
  end if;

  -- ── LEGACY (laufende Aktion, kein engine-Flag): Wort für Wort das bisherige Verhalten. ──
  if coalesce(k.config->>'engine','') <> 'generic' then
    if p_result = 'no_answer' then
      update public.call_leads set status='no_answer', followup_date=coalesce(p_date, current_date+2),
        reject_reason=null, appointment_date=null, appointment_time=null, note=p_note,
        updated_by=p_assignee, updated_at=now() where id=l.id;
      update public.cvs set last_worked_at=now() where id=l.cv_id;
    elsif p_result = 'rejected' then
      if p_reason is null or p_reason not in ('kein_interesse','zu_weit','hat_anderes') then raise exception 'Absagegrund erforderlich.'; end if;
      update public.call_leads set status='rejected', reject_reason=p_reason, followup_date=null,
        appointment_date=null, appointment_time=null, note=p_note, updated_by=p_assignee, updated_at=now() where id=l.id;
      update public.cvs set status='rejected_by_us', status_changed_at=now(), last_worked_at=now(),
        extra = coalesce(extra,'{}'::jsonb) || jsonb_build_object('reject_reason', p_reason, 'rejected_via','telefonaktion',
                'reject_note', coalesce(p_note,'')) where id=l.cv_id;
    elsif p_result = 'appointment' then
      if p_date is null then raise exception 'Termindatum erforderlich.'; end if;
      insert into public.calendar_events(title, description, kind, auto_key, start_date, start_time, created_by, created_by_name)
        values('Büro-Interview: '||coalesce(c.first_name,'')||' '||coalesce(c.last_name,''),
               'Telefonaktion → Einladung ins Büro. Tel: '||coalesce(c.phone,'—')||', Sprache: '||coalesce(c.language_level,'—')
                 ||case when coalesce(p_note,'')<>'' then E'\nNotiz: '||p_note else '' end,
               'manual', 'callcamp:'||l.id::text, p_date, t_time, p_assignee, nm)
        on conflict (auto_key) do update set start_date=excluded.start_date, start_time=excluded.start_time,
          description=excluded.description, updated_at=now() returning id into ev;
      update public.call_leads set status='appointment', appointment_date=p_date, appointment_time=t_time,
        reject_reason=null, followup_date=null, calendar_event_id=ev, note=p_note, updated_by=p_assignee, updated_at=now() where id=l.id;
      update public.cvs set status='interview', status_changed_at=now(), last_worked_at=now() where id=l.cv_id;
    else
      raise exception 'Unbekanntes Ergebnis: %', p_result;
    end if;
    return jsonb_build_object('ok', true, 'result', p_result);
  end if;

  -- ── GENERIC (config.engine='generic'): Wirkung aus config.buttons[key].effect. ──
  select btn into b from jsonb_array_elements(coalesce(k.config->'buttons','[]'::jsonb)) btn where btn->>'key' = p_result limit 1;
  if b is null then raise exception 'Unbekanntes Ergebnis: %', p_result; end if;
  eff := coalesce(b->'effect','{}'::jsonb);
  needs := coalesce(b->>'needs','none');
  newstatus := nullif(eff->>'cv_status','');
  do_cal := coalesce((eff->>'calendar')::boolean, false);
  do_bump := coalesce((eff->>'bump_last_worked')::boolean, false);

  if needs='reason' then
    if p_reason is null then raise exception 'Grund erforderlich.'; end if;
    select exists(select 1 from jsonb_array_elements(coalesce(b->'reasons','[]'::jsonb)) r where r->>0 = p_reason) into reason_ok;
    if not reason_ok then raise exception 'Ungültiger Grund.'; end if;
  elsif needs='datetime' then
    if p_date is null then raise exception 'Datum erforderlich.'; end if;
  end if;

  update public.call_leads set status=p_result,
    reject_reason   = case when needs='reason'   then p_reason else null end,
    followup_date   = case when needs='date'     then coalesce(p_date, current_date+2) else null end,
    appointment_date= case when needs='datetime' then p_date else null end,
    appointment_time= case when needs='datetime' then t_time else null end,
    note = p_note, calendar_event_id = null, updated_by=p_assignee, updated_at=now() where id=l.id;

  if do_cal and p_date is not null then
    insert into public.calendar_events(title, description, kind, auto_key, start_date, start_time, created_by, created_by_name)
      values(coalesce(nullif(eff->>'calendar_title',''),'Termin')||': '||coalesce(c.first_name,'')||' '||coalesce(c.last_name,''),
             coalesce(k.name,'Telefonaktion')||' → '||coalesce(b->>'label',p_result)||'. Tel: '||coalesce(c.phone,'—')
               ||case when coalesce(p_note,'')<>'' then E'\nNotiz: '||p_note else '' end,
             'manual', 'callcamp:'||l.id::text, p_date, t_time, p_assignee, nm)
      on conflict (auto_key) do update set start_date=excluded.start_date, start_time=excluded.start_time,
        description=excluded.description, updated_at=now() returning id into ev;
    update public.call_leads set calendar_event_id=ev where id=l.id;
  end if;

  if newstatus is not null then
    update public.cvs set status=newstatus, status_changed_at=now(),
      last_worked_at = case when do_bump then now() else last_worked_at end,
      extra = case when needs='reason' then coalesce(extra,'{}'::jsonb)
              || jsonb_build_object('reject_reason', p_reason, 'rejected_via','telefonaktion', 'reject_note', coalesce(p_note,''))
              else extra end
      where id=l.cv_id;
  elsif do_bump then
    update public.cvs set last_worked_at=now() where id=l.cv_id;
  end if;

  return jsonb_build_object('ok', true, 'result', p_result);
end $$;
grant execute on function public.phone_link_log(text, uuid, uuid, text, text, date, text, text) to anon, authenticated;

notify pgrst, 'reload schema';
