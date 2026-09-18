-- Schulungen als Link (Miriam): Schulung = eingefrorene Fragenkopie mit Lösung + drei Ebenen (Warum, Einwand, Anwendung),
-- öffentlicher Link-Token, Teilnehmer identifiziert sich per Mitarbeiter-PIN (time_pins) oder Gast-PIN (training_guests).
-- Öffentlicher Zugriff NUR über die Edge Function training-run (Service-Role); RLS hier nur für das HR-Portal.
create extension if not exists pgcrypto;

create table if not exists public.trainings (
  id uuid primary key default gen_random_uuid(),
  project_id text not null,
  title text not null,
  intro text,
  topics text[] not null default '{}',
  token text unique,
  status text not null default 'draft' check (status in ('draft','live','closed')),
  expires_at timestamptz,
  minutes_est int,
  questions jsonb not null default '[]'::jsonb,
  agent_key text not null default 'miriam',
  created_by uuid,
  created_by_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists trainings_project_idx on public.trainings(project_id, status);

create table if not exists public.training_guests (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  note text,
  active boolean not null default true,
  failed_attempts int not null default 0,
  locked_until timestamptz,
  created_by uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.training_runs (
  id uuid primary key default gen_random_uuid(),
  training_id uuid not null references public.trainings(id) on delete cascade,
  employee_id uuid,
  guest_id uuid references public.training_guests(id) on delete set null,
  name text not null,
  status text not null default 'running' check (status in ('running','done','abandoned')),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  seconds int,
  splits jsonb not null default '[]'::jsonb,
  answers jsonb not null default '[]'::jsonb,
  points numeric not null default 0,
  max int not null default 0,
  score numeric,
  summary text,
  updated_at timestamptz not null default now()
);
create index if not exists training_runs_training_idx on public.training_runs(training_id, started_at desc);

alter table public.trainings enable row level security;
alter table public.training_guests enable row level security;
alter table public.training_runs enable row level security;

drop policy if exists trainings_internal_read on public.trainings;
create policy trainings_internal_read on public.trainings for select to authenticated
  using (coalesce((perm(auth.uid(),'wissen')->>'visible')::boolean,false) and perm_proj_ok(auth.uid(),'wissen',project_id));
drop policy if exists trainings_internal_write on public.trainings;
create policy trainings_internal_write on public.trainings for all to authenticated
  using (perm_mode(auth.uid(),'wissen') = 'edit' and perm_proj_ok(auth.uid(),'wissen',project_id))
  with check (perm_mode(auth.uid(),'wissen') = 'edit' and perm_proj_ok(auth.uid(),'wissen',project_id));

drop policy if exists training_guests_internal on public.training_guests;
create policy training_guests_internal on public.training_guests for all to authenticated
  using (perm_mode(auth.uid(),'wissen') = 'edit') with check (perm_mode(auth.uid(),'wissen') = 'edit');

drop policy if exists training_runs_internal on public.training_runs;
create policy training_runs_internal on public.training_runs for select to authenticated
  using (exists (select 1 from public.trainings t where t.id = training_id
                 and coalesce((perm(auth.uid(),'wissen')->>'visible')::boolean,false) and perm_proj_ok(auth.uid(),'wissen',t.project_id)));
drop policy if exists training_runs_internal_del on public.training_runs;
create policy training_runs_internal_del on public.training_runs for delete to authenticated
  using (exists (select 1 from public.trainings t where t.id = training_id and perm_mode(auth.uid(),'wissen') = 'edit' and perm_proj_ok(auth.uid(),'wissen',t.project_id)));

-- PIN-Prüfung für die öffentliche Seite (nur über Service-Role aufgerufen): Mitarbeiter-PIN (time_pins) ODER Gast-PIN.
-- Rate-Limit über time_pin_attempts wie beim Stempeln (5 Fehlversuche in 5 Minuten sperren global).
create or replace function public.training_pin_check(p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_fails int; v_oldest timestamptz; v_pin time_pins%rowtype; v_emp employees%rowtype; v_g training_guests%rowtype;
begin
  select count(*), min(attempted_at) into v_fails, v_oldest from time_pin_attempts where attempted_at > now() - interval '5 minutes';
  if v_fails >= 5 then
    return jsonb_build_object('error','locked','retry_after_seconds', greatest(1, ceil(extract(epoch from (v_oldest + interval '5 minutes' - now())))::int));
  end if;
  select * into v_pin from time_pins where code = p_code;
  if found then
    if v_pin.locked_until is not null and v_pin.locked_until > now() then return jsonb_build_object('error','locked'); end if;
    select * into v_emp from employees where id = v_pin.emp_id;
    if found and coalesce(v_emp.status,'') not like 'terminated%' and coalesce(v_emp.status,'') not in ('rejected','blacklist') then
      return jsonb_build_object('ok', true, 'employee_id', v_emp.id, 'name', trim(coalesce(v_emp.first_name,'')||' '||coalesce(v_emp.last_name,'')), 'project_id', v_emp.project_id);
    end if;
  end if;
  select * into v_g from training_guests where code = p_code and active;
  if found then
    return jsonb_build_object('ok', true, 'guest_id', v_g.id, 'name', v_g.name);
  end if;
  delete from time_pin_attempts where attempted_at < now() - interval '1 hour';
  insert into time_pin_attempts default values;
  return jsonb_build_object('error','invalid');
end $$;
revoke all on function public.training_pin_check(text) from public, anon, authenticated;

-- Miriam: Trainerin, partnerunabhängig (System-Agent im Register)
insert into public.ai_agents (key, name, tagline, accent, domain, visibility, active, seq, persona, char_text, focus_text, language_text, capabilities, where_keys, disclosure)
values ('miriam', 'Miriam', 'Führt durch Schulungen: erklärt, löst auf, bewertet und gibt Rückmeldung.', '#b45309', 'Schulung', 'all', true, 7,
  'Klar, warm, konkret. Du erklärst, warum etwas so ist, und zeigst, wie man es im Gespräch sagt. Du lobst ehrlich und benennst Lücken ohne Umschweife. Nur aus den Unterlagen des jeweiligen Partners, nie erfunden; was nicht drinsteht, sagst du offen.',
  'Klar, warm, konkret. Du erklärst, warum etwas so ist, und zeigst, wie man es im Gespräch sagt.',
  'Schulungen per Link: Intro, Fragen mit Auflösung (Warum, Einwand, Anwendung), Bewertung, Rückmeldung am Ende.',
  'Deutsch, duzt Mitarbeiter. Kurze Sätze. Keine Gedankenstriche.',
  array['Schulungen aufbauen','Antworten bewerten','Rückmeldung schreiben'], array['schulungen'], 'Ich bin Miriam, eine KI-Trainerin von TIVE 360°. Ich führe durch diese Schulung.')
on conflict (key) do update set tagline = excluded.tagline, domain = excluded.domain, active = true, persona = excluded.persona, char_text = excluded.char_text, focus_text = excluded.focus_text, language_text = excluded.language_text;
