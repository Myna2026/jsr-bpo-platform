-- Claras Morgen-Zusammenfassung (Recruiting): Kennzahlen des Tages, aus echten Daten. „Wiederholer" und
-- „Dubletten" gibt es nicht als Feld → aus geteilter E-Mail/Telefon abgeleitet (ehrlich, mit Grenze).
create or replace function public.clara_morning_stats(p_date date default current_date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_new int; v_prev int; v_rep int; v_exp int; v_dub int;
  v_hoch int; v_mittel int; v_niedrig int; v_unb int;
begin
  if auth.uid() is not null and not public.is_admin() then raise exception 'not authorized'; end if;

  select count(*) into v_new  from public.cvs where created_at::date = p_date;
  select count(*) into v_prev from public.cvs where created_at::date = p_date - 1;

  -- Wiederholer: heute neu, aber E-Mail/Telefon war schon vorher da.
  select count(*) into v_rep from public.cvs t
   where t.created_at::date = p_date
     and exists (select 1 from public.cvs o where o.id <> t.id and o.created_at < p_date::timestamp
        and ((t.email is not null and t.email<>'' and lower(o.email)=lower(t.email))
          or (t.phone is not null and t.phone<>'' and o.phone=t.phone)));

  -- Sprachverteilung der heute Neuen.
  select
    count(*) filter (where language_level in ('C1','C2') or language_level ilike '%mutter%'),
    count(*) filter (where language_level in ('B1','B2')),
    count(*) filter (where language_level in ('A1','A2')),
    count(*) filter (where language_level is null or language_level=''),
    count(*) filter (where experience_years is not null)
  into v_hoch, v_mittel, v_niedrig, v_unb, v_exp
  from public.cvs where created_at::date = p_date;

  -- Dubletten zur Entscheidung: offene Bewerber (früher Trichter), die E-Mail/Telefon mit einem anderen teilen.
  select count(*) into v_dub from public.cvs c
   where c.status in ('cv_inbound','cv_accepted','cv_confirmed','invited','no_contact','parking')
     and exists (select 1 from public.cvs o where o.id <> c.id
        and ((c.email is not null and c.email<>'' and lower(o.email)=lower(c.email))
          or (c.phone is not null and c.phone<>'' and o.phone=c.phone)));

  return jsonb_build_object(
    'new_today', v_new, 'new_prev', v_prev, 'repeaters', v_rep,
    'lang', jsonb_build_object('hoch',v_hoch,'mittel',v_mittel,'niedrig',v_niedrig,'unbekannt',v_unb),
    'has_experience', v_exp, 'dubletten_pending', v_dub);
end $$;
revoke all on function public.clara_morning_stats(date) from public;
grant execute on function public.clara_morning_stats(date) to authenticated, service_role;
