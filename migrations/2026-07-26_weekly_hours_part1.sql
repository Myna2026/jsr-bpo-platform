-- weekly_hours aus extra in echte Spalte — TEIL 1 (VOR dem Code-Deploy).
-- Muster wie CV-Umbau: Spalte anlegen + aus extra kopieren, extra-Key BLEIBT vorerst
-- (Zero-Gap: solange der alte Code weiter nach extra schreibt). Teil 2 (extra-Cleanup)
-- erst NACH dem Code-Deploy. Kein Datenverlust: coalesce/where lässt vorhandene Werte gewinnen.
-- weekly_hours ist die Wochenstundenzahl (Lohn-/Stunden-Logik: monthly_hours > weekly_hours > daily).

alter table public.employees
  add column if not exists weekly_hours numeric;

update public.employees
  set weekly_hours = nullif(extra->>'weekly_hours','')::numeric
  where extra ? 'weekly_hours' and weekly_hours is null;
