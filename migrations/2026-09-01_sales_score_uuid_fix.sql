-- FIX: sales_leads.id ist UUID, nicht bigint. Die Scoring-Funktion war fälschlich bigint-typisiert → sales_recompute_scores
-- warf bei echten Leads einen Typfehler (fiel nur nicht auf, solange 0 Leads da waren). Neu als uuid, bigint-Overload raus.

drop function if exists public.sales_score_for(bigint);

create or replace function public.sales_score_for(p_lead_id uuid)
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

grant execute on function public.sales_score_for(uuid) to authenticated;

-- Neu binden (Plan-Cache) + Test.
create or replace function public.sales_recompute_scores()
returns int language plpgsql security definer set search_path=public as $$
declare r record; n int:=0;
begin
  if auth.uid() is not null and not is_sales_user() then raise exception 'kein Zugriff'; end if;
  for r in select id from sales_leads loop
    update sales_leads set score = sales_score_for(r.id) where id=r.id;
    n := n+1;
  end loop;
  return n;
end $$;
