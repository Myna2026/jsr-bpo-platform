-- Auswertung „nicht erschienen" je Quelle und Kampagne (User 2026-09-22).
-- Nenner ist die Zahl der GEBUCHTEN Termine im Zeitraum, nicht die Bewerberzahl: nur so ist die Quote ehrlich.
-- Zaehler kommt aus den Vermerken in cvs.extra.noshow.events (kind='noshow'|'cancel'), die der Knopf im Kanban schreibt.
-- Kampagne kommt ueber cvs.extra.lead_id -> windsor_leads.campaign (nur Meta-Bewerbungen haben eine).
-- Gezaehlt wird erst ab Einfuehrung des Knopfes; rueckwirkend gibt es die Daten nicht.
create or replace function public.noshow_stats(p_from date, p_to date)
returns jsonb language sql stable security definer set search_path = public as $$
with erlaubt as (
  select exists (select 1 from app_users a where a.user_id = auth.uid() and a.active is distinct from false
                   and a.role_keys && array['management','hr','projektleiter','teamlead']) as ok
),
quelle as (   -- Herkunft je Bewerbung, einheitlich benannt
  select c.id,
         case when lower(coalesce(c.source,'')) = 'meta' then 'Meta-Anzeigen'
              when lower(coalesce(c.source,'')) like '%sheet%' or lower(coalesce(c.source,'')) like '%google%' then 'Google-Sheet'
              when coalesce(c.source,'') = '' then 'ohne Angabe' else c.source end as src,
         nullif(w.campaign,'') as campaign
    from cvs c
    left join windsor_leads w on w.id::text = c.extra->>'lead_id'
),
termine as (  -- Nenner: gebuchte Termine im Zeitraum
  select q.src, q.campaign, count(*)::int as n
    from interview_invites i join quelle q on q.id = i.cv_id
   where i.status = 'booked' and i.booked_slot::date between p_from and p_to
   group by 1,2
),
vorfaelle as ( -- Zaehler: Vermerke im Zeitraum, getrennt nach Telefon und Buero
  select q.src, q.campaign, e->>'kind' as kind, e->>'phase' as phase, count(*)::int as n
    from cvs c
    join quelle q on q.id = c.id
    cross join lateral jsonb_array_elements(coalesce(c.extra->'noshow'->'events','[]'::jsonb)) e
   where (e->>'at')::timestamptz::date between p_from and p_to
   group by 1,2,3,4
)
select case when (select ok from erlaubt) then jsonb_build_object(
  'von', p_from, 'bis', p_to,
  'gesamt', jsonb_build_object(
     'termine', coalesce((select sum(n) from termine),0),
     'nicht_erschienen', coalesce((select sum(n) from vorfaelle where kind='noshow'),0),
     'telefon', coalesce((select sum(n) from vorfaelle where kind='noshow' and phase='phone'),0),
     'buero', coalesce((select sum(n) from vorfaelle where kind='noshow' and phase='office'),0),
     'abgesagt', coalesce((select sum(n) from vorfaelle where kind='cancel'),0)),
  'quellen', coalesce((select jsonb_agg(x order by x->>'quelle') from (
      select jsonb_build_object('quelle', s.src,
        'termine', coalesce((select sum(n) from termine t where t.src=s.src),0),
        'nicht_erschienen', coalesce((select sum(n) from vorfaelle v where v.src=s.src and v.kind='noshow'),0),
        'telefon', coalesce((select sum(n) from vorfaelle v where v.src=s.src and v.kind='noshow' and v.phase='phone'),0),
        'buero', coalesce((select sum(n) from vorfaelle v where v.src=s.src and v.kind='noshow' and v.phase='office'),0),
        'abgesagt', coalesce((select sum(n) from vorfaelle v where v.src=s.src and v.kind='cancel'),0)) as x
        from (select src from termine union select src from vorfaelle) s) q), '[]'::jsonb),
  'kampagnen', coalesce((select jsonb_agg(x order by (x->>'termine')::int desc) from (
      select jsonb_build_object('kampagne', k.campaign,
        'termine', coalesce((select sum(n) from termine t where t.campaign=k.campaign),0),
        'nicht_erschienen', coalesce((select sum(n) from vorfaelle v where v.campaign=k.campaign and v.kind='noshow'),0),
        'telefon', coalesce((select sum(n) from vorfaelle v where v.campaign=k.campaign and v.kind='noshow' and v.phase='phone'),0),
        'buero', coalesce((select sum(n) from vorfaelle v where v.campaign=k.campaign and v.kind='noshow' and v.phase='office'),0),
        'abgesagt', coalesce((select sum(n) from vorfaelle v where v.campaign=k.campaign and v.kind='cancel'),0)) as x
        from (select campaign from termine where campaign is not null union select campaign from vorfaelle where campaign is not null) k) c), '[]'::jsonb)
) else jsonb_build_object('error','keine Berechtigung') end;
$$;
revoke all on function public.noshow_stats(date, date) from public, anon;
grant execute on function public.noshow_stats(date, date) to authenticated, service_role;
-- Probe (im SQL-Fenster ohne auth.uid() erwartungsgemaess 'keine Berechtigung'):
-- select public.noshow_stats(current_date - 90, current_date);
