-- Postfach-Bereich: Management/HR duerfen mail_messages aktualisieren (gelesen-markieren + einem
-- Bewerber zuordnen). Lesen war schon erlaubt (mm_select). Schreiben der Mails selbst laeuft ueber die
-- Edge Functions (service role); diese Policy deckt nur die zwei UI-Aktionen ab. Deonita ist HR.
drop policy if exists mm_update on public.mail_messages;
create policy mm_update on public.mail_messages for update to authenticated
  using ( public.is_management() or public.is_hr() )
  with check ( public.is_management() or public.is_hr() );
