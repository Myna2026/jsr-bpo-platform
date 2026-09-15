-- Arbeitsplan vollwertig (Richtung Monday, ohne Ballast): je Punkt Verantwortlicher, Aufwand (Tage, Gewicht für
-- den Fortschritt), ein Vorgänger (Abhängigkeit). Alles additiv, bestehende Spalten/Policies bleiben.
-- Fortschritt Hauptpunkt = Σ(Aufwand × Fortschritt) / Σ Aufwand der Unterpunkte (Frontend rechnet).
-- Verantwortlicher als Name + Seite (Kundenlogin ist ein Firmen-Account, keine Personen → kein User-Pick).
-- Der Kunden-Guard-Trigger (imp_items_client_guard) lässt diese Spalten bewusst durch: Kunde pflegt sie mit.

alter table public.improvement_items add column if not exists effort_days int not null default 1 check (effort_days >= 1 and effort_days <= 365);
alter table public.improvement_items add column if not exists owner_name  text;
alter table public.improvement_items add column if not exists owner_side  text check (owner_side in ('client','team'));
alter table public.improvement_items add column if not exists depends_on  uuid references public.improvement_items(id) on delete set null;
create index if not exists improvement_items_dep_idx on public.improvement_items(depends_on) where depends_on is not null;

-- Kein Punkt hängt von sich selbst ab.
alter table public.improvement_items drop constraint if exists improvement_items_no_self_dep;
alter table public.improvement_items add constraint improvement_items_no_self_dep check (depends_on is null or depends_on <> id);
