-- Team-Chat-Rückbau: Der Chat war nie in Betrieb (dm_*-Tabellen fehlten in der DB) und wird bewusst entfernt.
-- Ein späterer Chat wird bewusst neu gebaut, mit Transparenz gegenüber den Mitarbeitern von Anfang an.
-- Die dm_*-RPCs (referenzierten die fehlenden Tabellen) werden gedroppt. Frontend-Chat (UI/Funktionen/CSS)
-- ist aus mitarbeiter.html entfernt. BEHALTEN: chat_universal_contacts (View) + loadUniversalContacts speisen
-- weiterhin den Roster/getEmpById im MA-Portal (nicht chat-exklusiv). Idempotent.
drop function if exists public.dm_add_member(uuid, uuid);
drop function if exists public.dm_can_chat(uuid);
drop function if exists public.dm_leave_group(uuid);
drop function if exists public.dm_remove_member(uuid, uuid);
drop function if exists public.dm_rename_group(uuid, text);
drop function if exists public.dm_set_translations(uuid, jsonb);
