-- Atomarer Sende-Anspruch je Bewerber: gibt id zurück, wenn frei (neu ODER Retry nach 'failed'),
-- sonst null (bereits 'sent'/'sending' → kein Doppelversand). Nutzt den partiellen Unique-Index
-- applicant_messages_jobfair_cv_uq(cv_id where purpose='jobfair').
create or replace function public.jobfair_claim(p_cv_id uuid, p_email text)
returns uuid language sql security definer set search_path=public as $$
  insert into public.applicant_messages(cv_id,purpose,channel,origin,sender_key,to_address,status)
  values (p_cv_id,'jobfair','email','campaign','recruiting',p_email,'sending')
  on conflict (cv_id) where purpose='jobfair'
    do update set status='sending', to_address=excluded.to_address, error=null, sent_at=null
    where applicant_messages.status='failed'
  returning id;
$$;
