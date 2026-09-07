-- Termine können einen Video-/Meeting-Link tragen (Teams/Zoom/…), im Termin als anklickbarer
-- „Beitreten"-Button. Additiv, kein Datenverlust. Danach die zwei Management-Weekly-Termine (Mo+Fr)
-- mit dem Teams-Link befüllt.

alter table public.calendar_events add column if not exists meeting_url text;

update public.calendar_events
   set meeting_url = 'https://teams.live.com/meet/9318841361559?p=cPUsVrjR7WOjs5bMtQ',
       updated_at  = now()
 where id in (
   'd16fdaee-4f78-478e-b8f8-5be62a646703',   -- Management Weekly (Montag 10:30)
   '36f61b90-db5c-4367-8afe-4266ac9570ff'    -- Management Weekly (Freitag 10:30)
 );
