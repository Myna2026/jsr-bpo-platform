-- =============================================================================
-- Terminkalender: Teilnehmer + „wichtig"-Kennzeichen + neue Sichtbarkeit   2026-08-04
-- =============================================================================
-- Sichtbarkeitsregel (in der RLS, nicht nur Anzeige):
--   Ein Termin ist sichtbar, wenn EINE davon zutrifft:
--     · Management/HR (is_admin()) — sieht alles
--     · selbst angelegt (created_by = auth.uid())
--     · Teilnehmer (get_my_employee_id() in participants)
--     · rollenbasiert (visible_roles && meine Rollen) — deckt die 4 Auto-Pflichttermine
--       (kind='auto', visible_roles={management,finance}), die KEINE Einzel-Teilnehmer haben.
--
-- Anlegen: jeder Eingeloggte (created_by muss = auth.uid()). Bearbeiten/Löschen: Ersteller
-- ODER Management/HR. Overrides (Erledigt/Ausblenden) folgen der Sichtbarkeit (Helfer unten).
--
-- participants = uuid[] von employees.id (kein FK auf Array-Elemente; verwaiste IDs matchen
-- niemanden = harmlos). important = optische Hervorhebung im Kalender (keine Aufgaben-Projektion).
--
-- Abhängig von is_admin()/get_my_employee_id()/get_my_role_keys(). Idempotent. Im SQL-Editor.
-- =============================================================================

alter table public.calendar_events
  add column if not exists participants uuid[] not null default '{}',
  add column if not exists important     boolean not null default false;

-- ── Sichtbarkeits-Helfer (für die Override-Policies; security definer = RLS-frei) ──
create or replace function public.calendar_event_visible(ev uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists (
    select 1 from public.calendar_events e
    where e.id = ev
      and ( public.is_admin()
            or e.created_by = auth.uid()
            or public.get_my_employee_id() = any(e.participants)
            or (e.visible_roles <> '{}'::text[] and e.visible_roles && public.get_my_role_keys()) )
  );
$$;

-- ── Events: Sichtbarkeit + neue Schreibrechte ────────────────────────────────
drop policy if exists cal_ev_select on public.calendar_events;
create policy cal_ev_select on public.calendar_events
  for select to authenticated
  using (
    public.is_admin()
    or created_by = auth.uid()
    or public.get_my_employee_id() = any(participants)
    or (visible_roles <> '{}'::text[] and visible_roles && public.get_my_role_keys())
  );

-- Anlegen: jeder Eingeloggte, aber nur als sich selbst (created_by = auth.uid()).
drop policy if exists cal_ev_insert on public.calendar_events;
create policy cal_ev_insert on public.calendar_events
  for insert to authenticated with check ( created_by = auth.uid() );

-- Bearbeiten/Löschen: Ersteller ODER Management/HR.
drop policy if exists cal_ev_update on public.calendar_events;
create policy cal_ev_update on public.calendar_events
  for update to authenticated
  using ( public.is_admin() or created_by = auth.uid() )
  with check ( public.is_admin() or created_by = auth.uid() );

drop policy if exists cal_ev_delete on public.calendar_events;
create policy cal_ev_delete on public.calendar_events
  for delete to authenticated
  using ( public.is_admin() or created_by = auth.uid() );

-- Override-Policies (cal_ovr_*) unverändert: sie rufen calendar_event_visible() → neue Regel greift automatisch.
