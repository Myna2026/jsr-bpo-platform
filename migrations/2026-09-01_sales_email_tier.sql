-- Sales-Akquise: Güte der Mailadresse (persönlich > Abteilung > allgemein). Persönlich = vorname.nachname@ (grün,
-- höchste Chance), Abteilung = vertrieb@/service@ (gelb), allgemein = info@/kontakt@/office@ (rot). Fließt in die
-- Bewertung ein und ist in der Liste sichtbar. Trigger hält email_tier für ALLE Wege konsistent (Liste/Apollo/Mail/manuell).

create or replace function public.sales_email_tier(p_email text)
returns text language plpgsql immutable as $$
declare lp text;
begin
  if p_email is null or position('@' in p_email)=0 then return null; end if;
  lp := lower(split_part(p_email,'@',1));
  lp := regexp_replace(lp,'\+.*$','');   -- plus-Adressierung weg
  if lp = any(array['info','kontakt','contact','office','mail','email','hello','hallo','hi','team','all','welcome','moin','zentrale','post','anfrage','anfragen','newsletter','no-reply','noreply']) then return 'general'; end if;
  if lp = any(array['vertrieb','sales','verkauf','service','support','kundenservice','kundenbetreuung','personal','hr','jobs','karriere','career','bewerbung','recruiting','marketing','presse','press','einkauf','buchhaltung','finance','accounting','it','admin','empfang','reception','beratung','betrieb']) then return 'department'; end if;
  if lp ~ '^[a-z]{2,}[._-][a-z]{2,}' then return 'personal'; end if;   -- vorname.nachname
  return 'department';                                                -- Einzelname unbekannt → vorsichtig Mitte
end $$;

alter table public.sales_leads add column if not exists email_tier text;

create or replace function public.sales_leads_set_tier() returns trigger language plpgsql as $$
begin new.email_tier := public.sales_email_tier(new.contact_email); return new; end $$;
drop trigger if exists trg_sales_leads_tier on public.sales_leads;
create trigger trg_sales_leads_tier before insert or update of contact_email on public.sales_leads
  for each row execute function public.sales_leads_set_tier();

update public.sales_leads set email_tier = public.sales_email_tier(contact_email);

-- Bewertung um die Mailadressen-Güte erweitern: persönlich +8, allgemein -8.
create or replace function public.sales_score_for(p_lead_id bigint)
returns numeric language plpgsql security definer set search_path=public as $$
declare l record; cfg jsonb; ind jsonb; iw numeric:=0;
  fit numeric:=0; reach numeric:=0; research numeric:=0; s numeric;
  n_sent int; n_open int; n_reply int; sz int; smin int; smax int; ssmin int; ssmax int; gb numeric;
begin
  select * into l from sales_leads where id=p_lead_id;
  if not found then return null; end if;
  if l.status in ('won','lost','dead','suppressed') then return 0; end if;
  select value into cfg from app_config where key='jsr_sales_fit_v1';

  if cfg is not null and coalesce(l.industry,'')<>'' then
    for ind in select * from jsonb_array_elements(cfg->'industries') loop
      if position(lower(ind->>'name') in lower(l.industry))>0
         or position(lower(split_part(ind->>'name',' ',1)) in lower(l.industry))>0 then
        iw := greatest(iw, coalesce((ind->>'weight')::numeric,0));
      end if;
    end loop;
  end if;
  fit := fit + iw*2;

  sz := l.company_size;
  smin := coalesce((cfg->'size'->>'min')::int, 0);      smax := coalesce((cfg->'size'->>'max')::int, 2000000000);
  ssmin := coalesce((cfg->'size'->>'sweet_min')::int, smin); ssmax := coalesce((cfg->'size'->>'sweet_max')::int, smax);
  if sz is null then fit := fit + 4;
  elsif sz between ssmin and ssmax then fit := fit + 14;
  elsif sz between smin and smax then fit := fit + 8;
  else fit := fit + 1; end if;

  gb := coalesce((cfg->>'growth_bonus')::numeric, 0);
  if coalesce(l.growth,'')<>'' then fit := fit + gb; end if;

  select count(*) filter (where kind='sent'), count(*) filter (where kind='opened'), count(*) filter (where kind='replied')
    into n_sent, n_open, n_reply from sales_events where lead_id=p_lead_id;
  if coalesce(n_reply,0)>0 then reach := reach + 25; end if;
  reach := reach + least(coalesce(n_open,0)*4, 12);
  if coalesce(n_sent,0)>=2 and coalesce(n_open,0)=0 and coalesce(n_reply,0)=0 then
    reach := reach - least((n_sent-1)*4, 16);
  end if;

  -- Mailadressen-Güte
  if l.email_tier = 'personal' then reach := reach + 8;
  elsif l.email_tier = 'general' then reach := reach - 8;
  end if;

  if coalesce(l.hook,'')<>'' then
    if coalesce((l.research->>'hook_general')::boolean,false) then research := 2; else research := 6; end if;
  end if;

  s := fit + reach + research;
  if s < 0 then s := 0; end if;
  return round(s,1);
end $$;

select public.sales_recompute_scores() as neu_bewertet;
