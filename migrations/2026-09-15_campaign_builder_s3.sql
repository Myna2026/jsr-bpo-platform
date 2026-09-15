
-- Schnitt 3: Aktionen anlegen + auflisten (Management/HR).
create or replace function public.campaign_list()
returns table(id uuid, name text, active boolean, date_from date, date_to date, public_token text,
  total int, done int, created_at timestamptz)
language sql stable security definer set search_path=public as $$
  select k.id, k.name, k.active, k.date_from, k.date_to, k.public_token,
    (select count(*) from public.call_leads l where l.campaign_id=k.id)::int,
    (select count(*) from public.call_leads l where l.campaign_id=k.id and l.status<>'open')::int,
    k.created_at
  from public.call_campaigns k
  where public.is_management() or public.is_hr()
  order by k.active desc, k.created_at desc;
$$;
grant execute on function public.campaign_list() to authenticated;

-- Neue Aktion: Name + Zeitraum. Default-Config = generischer Motor mit den 3 Recruiting-Knöpfen
-- (Knöpfe sind später je Aktion anpassbar). public_token wird automatisch vergeben (Default der Spalte).
create or replace function public.campaign_create(p_name text, p_from date default null, p_to date default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare new_id uuid; tok text;
begin
  if not (public.is_management() or public.is_hr()) then raise exception 'Nicht berechtigt.'; end if;
  if p_name is null or btrim(p_name)='' then raise exception 'Name erforderlich.'; end if;
  insert into public.call_campaigns(name, active, created_by, date_from, date_to, config)
  values (btrim(p_name), true, auth.uid(), p_from, p_to,
    '{"engine":"generic","buttons":[
       {"key":"no_answer","label":"Nicht erreicht","icon":"📵","style":"amber","needs":"date","date_label":"Wiedervorlage",
        "effect":{"cv_status":null,"calendar":false,"bump_last_worked":true}},
       {"key":"rejected","label":"Abgesagt","icon":"✗","style":"red","needs":"reason",
        "reasons":[["kein_interesse","Kein Interesse"],["zu_weit","Zu weit weg"],["hat_anderes","Hat schon was anderes"]],
        "effect":{"cv_status":"rejected_by_us","calendar":false,"bump_last_worked":true}},
       {"key":"appointment","label":"Termin","icon":"✅","style":"green","needs":"datetime","date_label":"Termin",
        "effect":{"cv_status":"interview","calendar":true,"bump_last_worked":true}}
     ]}'::jsonb)
  returning id, public_token into new_id, tok;
  return jsonb_build_object('ok',true,'id',new_id,'public_token',tok);
end $$;
grant execute on function public.campaign_create(text, date, date) to authenticated;
notify pgrst, 'reload schema';

-- Fix: public_token bekam beim Anlegen keinen Wert (Spalte ohne Default) -> Default ergaenzt.
alter table public.call_campaigns alter column public_token set default encode(gen_random_bytes(16),hex);
