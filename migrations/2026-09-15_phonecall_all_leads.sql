-- Auswertungstabelle Telefonaktion (HR-Portal): alle Leads eines Kampagnen, mgmt/hr.

create or replace function public.phonecall_all_leads(p_campaign uuid)
returns table(lead_id uuid, cv_name text, assignee_name text, status text, reject_reason text,
  followup_date date, appointment_date date, appointment_time time, note text, updated_at timestamptz)
language sql stable security definer set search_path=public as $$
  select l.id, btrim(coalesce(c.first_name,'')||' '||coalesce(c.last_name,'')), l.assignee_name, l.status,
    l.reject_reason, l.followup_date, l.appointment_date, l.appointment_time, l.note, l.updated_at
  from public.call_leads l join public.cvs c on c.id=l.cv_id
  where l.campaign_id=p_campaign and (public.is_management() or public.is_hr())
  order by l.assignee_name, c.last_name;
$$;
grant execute on function public.phonecall_all_leads(uuid) to authenticated;
notify pgrst, 'reload schema';
