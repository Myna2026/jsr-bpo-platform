-- Coach S5: Meldungen abarbeiten (flag_resolved_at) + interne Schreibrechte auf Antworten (nur Meldungs-Erledigung) und Fragen (sperren).
alter table public.coach_answers add column if not exists flag_resolved_at timestamptz;
drop policy if exists coach_a_internal_update on public.coach_answers;
create policy coach_a_internal_update on public.coach_answers for update to authenticated
  using (perm_mode(auth.uid(),'wissen') = 'edit' and perm_proj_ok(auth.uid(),'wissen',project_id))
  with check (perm_mode(auth.uid(),'wissen') = 'edit' and perm_proj_ok(auth.uid(),'wissen',project_id));
