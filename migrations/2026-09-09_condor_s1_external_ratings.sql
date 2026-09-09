-- Condor S1: zweite Bewertungsebene (extern) + Kundengrenze. Intern bewertet Ardita/HR, extern bewertet Condor
-- über einen EIGENEN Bogen. `rater_kind` trennt beide. Condor schreibt/liest NUR externe Samples des eigenen
-- Projekts und sieht NIE interne Bewertungen (client_call_scores wird extern-only).
-- Additiv; bestehende Samples/Bögen werden per Default 'intern' (= die heutigen internen Bewertungen).

-- ── 1) rater_kind (intern | extern) ────────────────────────────────────────
alter table public.call_samples  add column if not exists rater_kind text not null default 'intern';
alter table public.call_samples  drop constraint if exists call_samples_rater_kind_chk;
alter table public.call_samples  add  constraint call_samples_rater_kind_chk check (rater_kind in ('intern','extern'));

alter table public.call_criteria add column if not exists rater_kind text not null default 'intern';
alter table public.call_criteria drop constraint if exists call_criteria_rater_kind_chk;
alter table public.call_criteria add  constraint call_criteria_rater_kind_chk check (rater_kind in ('intern','extern'));

-- ── 2) Kunden-Policies (kunde: get_my_client_project_id() liefert sein Projekt, sonst NULL) ──
-- Externen Bogen des eigenen Projekts lesen (um das Formular zu rendern)
drop policy if exists call_criteria_client_read on public.call_criteria;
create policy call_criteria_client_read on public.call_criteria for select to authenticated
  using (rater_kind='extern'
    and public.get_my_client_project_id() is not null
    and project_id = public.get_my_client_project_id());

-- Eigene EXTERNE Samples lesen (nie interne) und anlegen (nur eigene Projekt-Mitarbeiter)
drop policy if exists call_samples_client_read on public.call_samples;
create policy call_samples_client_read on public.call_samples for select to authenticated
  using (rater_kind='extern'
    and public.get_my_client_project_id() is not null
    and project_id = public.get_my_client_project_id());
drop policy if exists call_samples_client_insert on public.call_samples;
create policy call_samples_client_insert on public.call_samples for insert to authenticated
  with check (rater_kind='extern'
    and public.get_my_client_project_id() is not null
    and project_id = public.get_my_client_project_id()
    and exists (select 1 from public.employees e
                 where e.id = employee_id and e.project_id = public.get_my_client_project_id()));

-- Scores zu den eigenen externen Samples lesen + anlegen
drop policy if exists call_scores_client_read on public.call_scores;
create policy call_scores_client_read on public.call_scores for select to authenticated
  using (exists (select 1 from public.call_samples s
                  where s.id = call_scores.sample_id and s.rater_kind='extern'
                    and public.get_my_client_project_id() is not null
                    and s.project_id = public.get_my_client_project_id()));
drop policy if exists call_scores_client_insert on public.call_scores;
create policy call_scores_client_insert on public.call_scores for insert to authenticated
  with check (exists (select 1 from public.call_samples s
                       where s.id = call_scores.sample_id and s.rater_kind='extern'
                         and public.get_my_client_project_id() is not null
                         and s.project_id = public.get_my_client_project_id()));

-- ── 3) client_call_scores → NUR EXTERN (Condor sieht keine internen Bewertungen mehr) ──
create or replace view public.client_call_scores with ("security_invoker"='off') as
 select s.id, s.employee_id,
    trim(both from ((coalesce(e.first_name,''::text) || ' '::text) || coalesce(e.last_name,''::text))) as employee_name,
    s.project_id, s.skill, s.total_pct, s.sampled_date, s.kw, s.year,
    s.total_points, s.max_points, s.raw_points, s.compliance_failed
   from public.call_samples s
     join public.employees e on e.id = s.employee_id
  where s.status = 'done'
    and s.rater_kind = 'extern'
    and s.project_id = public.get_my_client_project_id();
