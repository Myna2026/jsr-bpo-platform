-- =============================================================================
-- Kundenportal Organigramm: Kunde liest org_nodes SEINES Projekts (read-only).
-- =============================================================================
-- org_nodes wird bisher NUR in hr.html gelesen/geschrieben (Management/HR). Kein anderer
-- Frontend-Pfad liest die Tabelle. Deshalb ist RLS-Aktivieren + HR-Vollzugriff + Kunde-SELECT
-- unbedenklich für Bestandsnutzer.
--
-- org_nodes hat KEINE sensiblen Spalten (nur Struktur: title/subtitle/color/skill/parent_id/seq +
-- employees = Mitarbeiter-ID-Array). Namen löst client.html über die spaltenreduzierte
-- employees_client_view auf (kein Gehalt). Nicht auflösbare IDs (ausgeschieden/Projektwechsel)
-- fallen im Frontend still weg.
--
-- Zeilen-Scope für Kunden: nur eigenes Projekt (get_my_client_project_id() aus 25e).
-- Im Supabase SQL-Editor ausführen.
-- =============================================================================

alter table public.org_nodes enable row level security;

-- Management/HR/Finance: voller Zugriff (Chart bauen/bearbeiten). Sichert die Bestands-Bearbeitung
-- auch dann ab, falls RLS hier gerade erst aktiviert wurde.
drop policy if exists "HR full access org_nodes" on public.org_nodes;
create policy "HR full access org_nodes" on public.org_nodes
  for all to authenticated
  using      (exists (select 1 from app_users where user_id=auth.uid() and role_keys && array['management','hr','finance']::text[]))
  with check (exists (select 1 from app_users where user_id=auth.uid() and role_keys && array['management','hr','finance']::text[]));

-- Kunde: nur SELECT, nur eigenes Projekt.
drop policy if exists "Client reads own project org" on public.org_nodes;
create policy "Client reads own project org" on public.org_nodes
  for select to authenticated
  using (
    project_id = get_my_client_project_id()
    and exists (select 1 from app_users where user_id=auth.uid() and role_keys && array['kunde']::text[])
  );

grant select on public.org_nodes to authenticated;
