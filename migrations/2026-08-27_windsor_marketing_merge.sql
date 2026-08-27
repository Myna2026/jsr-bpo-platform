-- windsor_marketing: Instagram liefert je Tag ZWEI Zeilen (eine mit reach, eine mit followers_count), beide
-- ohne campaign → Kollision auf UNIQUE NULLS NOT DISTINCT (datasource,date,campaign). Windsor schreibt direkt
-- (delete-then-insert), darum lösen wir es DB-seitig: BEFORE-INSERT-Trigger führt eine kollidierende Zeile in
-- die bestehende zusammen (feldweise coalesce, neuer Wert gewinnt) statt zu scheitern. Eine Zeile pro Tag/Quelle,
-- Schlüssel bleibt unverändert. Entsperrt zugleich Facebook + Bewerbungen (gleicher Windsor-Lauf).
create or replace function public.windsor_marketing_merge() returns trigger
language plpgsql as $$
begin
  update public.windsor_marketing set
    account_name    = coalesce(new.account_name, account_name),
    source          = coalesce(new.source, source),
    spend           = coalesce(new.spend, spend),
    impressions     = coalesce(new.impressions, impressions),
    clicks          = coalesce(new.clicks, clicks),
    reach           = coalesce(new.reach, reach),
    followers_count = coalesce(new.followers_count, followers_count)
  where datasource is not distinct from new.datasource
    and date       is not distinct from new.date
    and campaign   is not distinct from new.campaign;
  if found then return null; end if;   -- in bestehende Zeile gemergt → Insert überspringen
  return new;                          -- keine Kollision → normal einfügen
end $$;

drop trigger if exists trg_windsor_marketing_merge on public.windsor_marketing;
create trigger trg_windsor_marketing_merge before insert on public.windsor_marketing
  for each row execute function public.windsor_marketing_merge();
