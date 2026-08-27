-- windsor_marketing: der BEFORE-ROW-Merge greift nicht bei zwei Zeilen im SELBEN INSERT (eine sieht die andere
-- aus demselben Befehl nicht) und auch echte Dubletten scheitern. Lösung: Unique-Constraint DEFERRABLE INITIALLY
-- DEFERRED (Prüfung erst beim Commit) + AFTER-STATEMENT-Trigger, der alle Mehrfach-Keys zu EINER Zeile mergt
-- (löschen + eine gemergte neu einfügen, non-null gewinnt via max). Rekursionsschutz gegen das Re-Insert.
drop trigger if exists trg_windsor_marketing_merge on public.windsor_marketing;

alter table public.windsor_marketing drop constraint if exists windsor_marketing_dsc_key;
alter table public.windsor_marketing add constraint windsor_marketing_dsc_key
  unique nulls not distinct (datasource, date, campaign) deferrable initially deferred;

create or replace function public.windsor_marketing_dedup() returns trigger
language plpgsql as $$
begin
  if pg_trigger_depth() > 1 then return null; end if;   -- Re-Insert unten nicht erneut deduppen
  drop table if exists _wm_merge;
  create temp table _wm_merge as
    select datasource, date, campaign,
      max(account_name) account_name, max(source) source, max(spend) spend, max(impressions) impressions,
      max(clicks) clicks, max(reach) reach, max(followers_count) followers_count
    from public.windsor_marketing
    group by datasource, date, campaign
    having count(*) > 1;
  if (select count(*) from _wm_merge) = 0 then drop table _wm_merge; return null; end if;
  delete from public.windsor_marketing d
   where exists (select 1 from _wm_merge m where m.datasource is not distinct from d.datasource
     and m.date is not distinct from d.date and m.campaign is not distinct from d.campaign);
  insert into public.windsor_marketing(datasource,date,campaign,account_name,source,spend,impressions,clicks,reach,followers_count)
    select datasource,date,campaign,account_name,source,spend,impressions,clicks,reach,followers_count from _wm_merge;
  drop table _wm_merge;
  return null;
end $$;

drop trigger if exists trg_windsor_marketing_dedup on public.windsor_marketing;
create trigger trg_windsor_marketing_dedup after insert on public.windsor_marketing
  for each statement execute function public.windsor_marketing_dedup();
