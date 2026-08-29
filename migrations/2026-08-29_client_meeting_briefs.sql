-- Vorhaben 2, Schnitt 2: Pauls erzeugte Termin-Briefings speichern (Historie + Schnitt-3-Seite lädt daraus).
-- facts = der deterministische Fakten-Stand (client_meeting_prep), sections = die vier Blöcke (KI, an den Zahlen belegt).
create table if not exists public.client_meeting_briefs (
  id           uuid primary key default gen_random_uuid(),
  project_id   text not null,
  generated_at timestamptz not null default now(),
  generated_by uuid,
  facts        jsonb,
  sections     jsonb          -- { gut:[], fragen:[], schwach:[], antwort:[] }
);
create index if not exists client_meeting_briefs_proj on public.client_meeting_briefs(project_id, generated_at desc);
alter table public.client_meeting_briefs enable row level security;
drop policy if exists cmb_rw on public.client_meeting_briefs;
create policy cmb_rw on public.client_meeting_briefs for all
  using      (public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()))
  with check (public.is_management() or (public.is_planner() and project_id = public.get_my_employee_project_id()));
grant select, insert on public.client_meeting_briefs to authenticated;
