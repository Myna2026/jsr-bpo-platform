-- Fehlerbezeichnung je Score einfrieren: bei kritischen Fehlern steht der Fehler (z. B. „Datenschutz verletzt")
-- im hint des Kriteriums, der prompt ist positiv formuliert. Anzeige „Kritischer Fehler: <hint>" braucht den Snapshot.
alter table public.call_scores add column if not exists hint_snapshot text;
