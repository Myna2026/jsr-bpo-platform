-- Anreicherungs-Fassungen (Strecken): benannte Varianten mit an-/abschaltbaren Abschnitten. Beim Link-Erzeugen
-- wählt HR eine Fassung. Test-Links sind mehrfach nutzbar (reusable), echte einmalig.

create table if not exists public.cv_enrich_forms (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  sections   jsonb not null default '{}'::jsonb,   -- {contact,birthday,language,audio,education,experience,availability,writing_sample}
  seq        int not null default 0,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.cv_enrich_forms enable row level security;
drop policy if exists cv_enrich_forms_sel on public.cv_enrich_forms;
drop policy if exists cv_enrich_forms_write on public.cv_enrich_forms;
create policy cv_enrich_forms_sel on public.cv_enrich_forms for select to authenticated using (true);
create policy cv_enrich_forms_write on public.cv_enrich_forms for all to authenticated using (is_management()) with check (is_management());
grant select, insert, update, delete on public.cv_enrich_forms to authenticated;

-- Vollversion als Default-Fassung (alle Abschnitte an).
insert into public.cv_enrich_forms(name, seq, sections)
select 'Vollversion (alles)', 0,
  '{"contact":true,"birthday":true,"language":true,"audio":true,"education":true,"experience":true,"availability":true,"writing_sample":true}'::jsonb
where not exists (select 1 from public.cv_enrich_forms);

-- Invite um Fassung + Mehrfachnutzung erweitern.
alter table public.cv_enrich_invites add column if not exists form_id uuid references public.cv_enrich_forms(id) on delete set null;
alter table public.cv_enrich_invites add column if not exists reusable boolean not null default false;

-- RPC neu: nimmt Fassung + reusable entgegen (Default backward-kompatibel = keine Fassung, einmalig).
drop function if exists public.create_cv_enrich_invite(uuid);
create or replace function public.create_cv_enrich_invite(p_cv_id uuid, p_form_id uuid default null, p_reusable boolean default false)
returns text language plpgsql security definer set search_path = public as $$
declare v_token text;
begin
  insert into cv_enrich_invites(cv_id, created_by, form_id, reusable)
    values (p_cv_id, auth.uid(), p_form_id, p_reusable)
    returning token into v_token;
  return v_token;
end $$;
grant execute on function public.create_cv_enrich_invite(uuid, uuid, boolean) to authenticated;
