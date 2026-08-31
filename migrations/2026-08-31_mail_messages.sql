-- Mail-Kontext-Lösung, Schnitt 1: einheitlicher Thread-Speicher mail_messages (Inhalt + Threading), verknüpft mit
-- Bewerber (cv_id) ODER Mitarbeiter (employee_id). Nur Sammelpostfächer (hr@/recruiting@25hrs.net), keine
-- persönlichen Postfächer (Datenschutz). Schreiben nur service_role (Mailer/Poller/Kompose-RPC) → Freitext-Guardrail
-- bleibt; keine authenticated-Inserts. Lesen im Kontext: Management/HR alles; Bewerber-Mail für Bewerber-Zugriff;
-- Mitarbeiter sieht seine eigene. (applicant_messages bleibt als reines Sende-Log bestehen, unabhängig.)

create table if not exists public.mail_messages (
  id uuid primary key default gen_random_uuid(),
  direction text not null check (direction in ('in','out')),
  mailbox text,                                                   -- 'hr' | 'recruiting'
  cv_id uuid references public.cvs(id) on delete set null,
  employee_id uuid references public.employees(id) on delete set null,
  from_address text,
  to_address text,
  subject text,
  body_text text,
  body_html text,
  message_id text,                                                -- <uuid@25hrs.net> fürs Threading
  in_reply_to text,                                               -- Message-ID der Vorgänger-Mail
  status text,                                                    -- out: sent|failed ; in: received
  error text,
  occurred_at timestamptz not null default now(),                 -- gesendet bzw. empfangen
  created_at timestamptz not null default now()
);
create index if not exists mail_messages_cv_idx on public.mail_messages(cv_id);
create index if not exists mail_messages_emp_idx on public.mail_messages(employee_id);
create index if not exists mail_messages_mid_idx on public.mail_messages(message_id);
create index if not exists mail_messages_occ_idx on public.mail_messages(occurred_at);

alter table public.mail_messages enable row level security;

-- Lesen im Kontext. Schreiben absichtlich KEINE authenticated-Policy → nur service_role (Edge Functions) schreibt.
drop policy if exists mm_select on public.mail_messages;
create policy mm_select on public.mail_messages for select to authenticated
using (
  public.is_management() or public.is_hr()
  or (cv_id is not null and public.perm_mode(auth.uid(),'bewerber') <> 'none')
  or (employee_id is not null and employee_id = public.perm_caller_emp_id())
);
