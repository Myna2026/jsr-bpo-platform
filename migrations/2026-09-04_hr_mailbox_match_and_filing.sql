-- Schnitt 1 der hr@-Postfach-Anbindung: Mitarbeiter-Zuordnung + Ablage-Trennung.
--
-- (1) match_employee_by_email: analog match_cv_by_email, aber gegen employees.email UND employees.email_internal
--     (case-insensitiv + getrimmt). Liefert die employee_id für die automatische POSTFACH-Zuordnung eingehender
--     hr@-Mails. Das ist reine Triage ("wen betrifft die Mail"), NICHT die Personalakte.
create or replace function public.match_employee_by_email(p_email text)
returns uuid
language sql
security definer
set search_path to 'public'
stable
as $$
  select id from public.employees
  where nullif(btrim(coalesce(p_email,'')),'') is not null
    and ( lower(btrim(coalesce(email,'')))          = lower(btrim(p_email))
       or lower(btrim(coalesce(email_internal,''))) = lower(btrim(p_email)) )
  order by updated_at desc nulls last
  limit 1
$$;
grant execute on function public.match_employee_by_email(text) to authenticated, service_role;

-- (2) Ablage-Trennung: nicht jede hr@-Mail gehört in die Akte (Krankmeldungen, Lohnfragen bleiben im Postfach
--     sichtbar, aber nicht automatisch am Profil). employee_id = Postfach-Zuordnung (automatisch); filed_at =
--     bewusst "in die Akte" gelegt (manuell, Knopf). Die Personalakte/das Profil zeigt später NUR Mails mit
--     filed_at IS NOT NULL. filed_by = wer abgelegt hat (Audit).
alter table public.mail_messages add column if not exists filed_at timestamptz;
alter table public.mail_messages add column if not exists filed_by uuid;
comment on column public.mail_messages.filed_at is 'Manuell "in die Akte" gelegt (NULL = nur im Postfach, nicht in der Personalakte).';
comment on column public.mail_messages.filed_by is 'auth.uid() der Person, die die Mail in die Akte gelegt hat.';

-- Schneller Zugriff auf die Akte eines Mitarbeiters (nur abgelegte Mails).
create index if not exists mail_messages_employee_filed_idx
  on public.mail_messages (employee_id, filed_at)
  where employee_id is not null and filed_at is not null;
