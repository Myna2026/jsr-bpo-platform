-- Tägliche Nutzungs-Zusammenfassung (Maya) + 30-Tage-Verlauf. Management-only.
-- usage_day_metrics: je (Tag, Nutzer) verdichtete Kennzahlen aus user_sessions + activity_log + daily_tasks_done.
--   Speist BEIDES: die tägliche KI-Zusammenfassung (Edge Function usage-digest) und den 30-Tage-Verlauf (Frontend).
-- usage_digests: der eine gespeicherte KI-Satz je Nutzer/Tag (damit die Ansicht nicht bei jedem Aufruf KI ruft).

begin;

-- ── Verdichtete Tages-Kennzahlen je Nutzer ────────────────────────────────────
-- Gate: authentifizierte Nutzer müssen Management sein; die Edge Function (service role, auth.uid()=NULL)
-- darf rechnen. Anon kann die Funktion nicht ausführen (kein Grant).
create or replace function public.usage_day_metrics(p_from date, p_to date)
returns table(
  day date, user_id uuid, user_name text,
  sessions int, active_minutes int, logins int,
  writes int, writes_by_entity jsonb, areas text[],
  tasks_done int, tasks_empty int
)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.is_management() then
    raise exception 'not authorized';
  end if;
  return query
  with
  sess as (
    select s.user_id as uid, s.started_at::date as d,
           count(*)::int as n,
           round(sum(greatest(0, extract(epoch from (s.last_seen - s.started_at))/60)))::int as mins
    from public.user_sessions s
    where s.started_at::date between p_from and p_to
    group by s.user_id, s.started_at::date
  ),
  acts as (
    select l.user_id as uid, l.created_at::date as d, l.action as action, l.entity as entity
    from public.activity_log l
    where l.created_at::date between p_from and p_to and l.user_id is not null
  ),
  logins as ( select uid, d, count(*)::int as n from acts where action='login' group by uid, d ),
  wr as (
    select uid, d, coalesce(entity,'-') as entity, count(*)::int as c
    from acts where action in ('create','update','delete') group by uid, d, coalesce(entity,'-')
  ),
  wr_agg as (
    select uid, d, sum(c)::int as total, jsonb_object_agg(entity, c) as byentity
    from wr group by uid, d
  ),
  vw as (
    select uid, d, array_agg(distinct entity) as areas
    from acts where action='view' and entity is not null group by uid, d
  ),
  tasks as (
    select t.done_by as uid, t.done_at::date as d, count(*)::int as n,
           count(*) filter (where t.session_writes = 0)::int as empty   -- NULL (vor Instrumentierung) zählt NICHT als leer
    from public.daily_tasks_done t
    where t.done_at::date between p_from and p_to and t.done_by is not null
    group by t.done_by, t.done_at::date
  ),
  keys as (
    select uid, d from sess
    union select uid, d from acts
    union select uid, d from tasks
  )
  select k.d, k.uid,
    coalesce((select au.full_name from public.app_users au where au.user_id = k.uid), '') as user_name,
    coalesce(se.n,0), coalesce(se.mins,0), coalesce(lo.n,0),
    coalesce(wa.total,0), coalesce(wa.byentity, '{}'::jsonb), coalesce(vw.areas, '{}'::text[]),
    coalesce(ta.n,0), coalesce(ta.empty,0)
  from (select distinct uid, d from keys) k
  left join sess   se on se.uid=k.uid and se.d=k.d
  left join logins lo on lo.uid=k.uid and lo.d=k.d
  left join wr_agg wa on wa.uid=k.uid and wa.d=k.d
  left join vw     vw on vw.uid=k.uid and vw.d=k.d
  left join tasks  ta on ta.uid=k.uid and ta.d=k.d
  order by k.d desc, user_name;
end $$;
revoke all    on function public.usage_day_metrics(date, date) from public;
grant execute on function public.usage_day_metrics(date, date) to authenticated;

-- ── Gespeicherte KI-Sätze (ein Satz je Nutzer/Tag) ───────────────────────────
create table if not exists public.usage_digests (
  day        date not null,
  user_id    uuid not null,
  user_name  text,
  summary    text,
  metrics    jsonb,
  created_at timestamptz not null default now(),
  primary key (day, user_id)
);
alter table public.usage_digests enable row level security;
drop policy if exists usage_digests_sel on public.usage_digests;
create policy usage_digests_sel on public.usage_digests for select to authenticated using (public.is_management());
grant select on public.usage_digests to authenticated;
-- Geschrieben ausschließlich von der Edge Function (service role, umgeht RLS) — keine authenticated-Insert-Policy.

commit;
