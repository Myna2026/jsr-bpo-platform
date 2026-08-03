-- =============================================================================
-- Rollenbezogene Tagesaufgaben — Schnitt 1: intern/extern-Kennzeichen am Zugang.
-- =============================================================================
-- "Manager extern" (Thorsten, Rajner) hat DIESELBEN Rechte/Sichtbarkeit wie internes
-- Management, aber KEINE eigene Aufgaben-Partition — nur die Zusammenschau. Das ist kein
-- eigener Rechtesatz, also keine neue Rolle, sondern ein Kennzeichen am Zugang.
--
-- Als Spalte in app_users (nicht app_config), damit es in DERSELBEN Abfrage wie role_keys
-- ankommt (gate()/gateSession() lesen app_users pro auth.uid()). Boolean, Default false;
-- für Nicht-Management-Rollen ohne Wirkung. RLS unverändert (Nutzer liest seine eigene Zeile,
-- Admin verwaltet) — eine neue, nicht-sensible Spalte ändert daran nichts.
-- Im Supabase SQL-Editor ausführen. Idempotent.
-- =============================================================================

alter table public.app_users
  add column if not exists mgmt_external boolean not null default false;

comment on column public.app_users.mgmt_external is
  'Management-Zugang OHNE eigene Aufgaben-Partition (Manager extern). Gleiche Rechte/Sichtbarkeit '
  'wie internes Management; steuert NUR, ob eine eigene Tagesaufgaben-Liste erzeugt wird. '
  'Für Nicht-Management-Rollen ohne Wirkung.';
