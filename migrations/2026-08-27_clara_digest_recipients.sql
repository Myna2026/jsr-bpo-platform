-- Empfänger von Claras Morgen-Zusammenfassung. Leicht erweiterbar: weitere Objekte anhängen
-- ({name,email,slack_email,active}). Start: nur Test an mich. Shkurte/Deonita/Rajner/Thorsten später.
insert into public.app_config(key, value) values ('jsr_clara_digest_recipients_v1',
  '[{"name":"Simon","email":"info@mynaai.de","slack_email":"info@mynaai.de","active":true}]'::jsonb)
on conflict (key) do nothing;
