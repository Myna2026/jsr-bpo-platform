-- Telefonaktion: Übersicht + Auswertung auch im Link (token-basiert, anon).

create or replace function public.phone_link_overview(p_token text)
returns table(assignee_user_id uuid, assignee_name text, total int, open int, no_answer int, rejected int, appointment int, followups_due int)
language sql stable security definer set search_path=public as $$
  select l.assignee_user_id, max(l.assignee_name), count(*)::int,
    count(*) filter (where l.status='open')::int, count(*) filter (where l.status='no_answer')::int,
    count(*) filter (where l.status='rejected')::int, count(*) filter (where l.status='appointment')::int,
    count(*) filter (where l.status='no_answer' and l.followup_date is not null and l.followup_date<=current_date)::int
  from public.call_campaigns k join public.call_leads l on l.campaign_id=k.id
  where k.public_token=p_token and k.active
  group by l.assignee_user_id order by max(l.assignee_name);
$$;
create or replace function public.phone_link_all(p_token text)
returns table(lead_id uuid, cv_name text, assignee_name text, status text, reject_reason text,
  followup_date date, appointment_date date, appointment_time time, note text, updated_at timestamptz)
language sql stable security definer set search_path=public as $$
  select l.id, btrim(coalesce(c.first_name,'')||' '||coalesce(c.last_name,'')), l.assignee_name, l.status,
    l.reject_reason, l.followup_date, l.appointment_date, l.appointment_time, l.note, l.updated_at
  from public.call_campaigns k join public.call_leads l on l.campaign_id=k.id join public.cvs c on c.id=l.cv_id
  where k.public_token=p_token and k.active
  order by l.assignee_name, c.last_name;
$$;
revoke all on function public.phone_link_overview(text) from public;
revoke all on function public.phone_link_all(text) from public;
grant execute on function public.phone_link_overview(text) to anon, authenticated;
grant execute on function public.phone_link_all(text) to anon, authenticated;
notify pgrst, 'reload schema';
