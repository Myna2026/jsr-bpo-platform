-- Robuste Bewerber-Zuordnung per E-Mail: case-insensitiv + getrimmt, gegen das EINE Adressfeld cvs.email.
-- (better_email ist ein boolean-Flag, KEIN zweites Adressfeld — der frühere Auto-Match nutzte es fälschlich
-- wie eine Adresse, wodurch die ganze Abfrage ungültig war und niemand zugeordnet wurde.)
create or replace function public.match_cv_by_email(p_email text)
returns uuid language sql stable security definer set search_path=public as $$
  select id from public.cvs
  where nullif(btrim(email),'') is not null
    and lower(btrim(email)) = lower(btrim(p_email))
  order by updated_at desc nulls last
  limit 1
$$;
grant execute on function public.match_cv_by_email(text) to authenticated, service_role;
