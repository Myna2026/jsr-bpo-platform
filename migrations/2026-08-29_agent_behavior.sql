-- Verhaltensregeln je Agent, editierbare Ebene in drei getrennte Felder (bisher ein persona-Blob):
--   char_text     = Charakter (Ton, Direktheit, Wortwahl)
--   focus_text    = Fachliche Ausrichtung (worauf achtet er, was meldet er, ab welcher Schwelle)
--   language_text = Sprachregeln
-- Die Functions lesen weiterhin persona; das Frontend komponiert persona beim Speichern aus den drei Feldern.
-- Rechte bleiben wie gehabt: SELECT nach visibility (wer den Agenten sieht, liest die Config), WRITE nur is_management().
alter table public.ai_agents add column if not exists char_text     text;
alter table public.ai_agents add column if not exists focus_text    text;
alter table public.ai_agents add column if not exists language_text text;

-- Backfill: der bestehende persona-Blob wandert in Charakter (Verhalten bleibt identisch, da persona = char_text,
-- solange focus/language leer sind). Management kann die Anteile später sauber in die eigenen Felder ziehen.
update public.ai_agents set char_text = persona where char_text is null;
