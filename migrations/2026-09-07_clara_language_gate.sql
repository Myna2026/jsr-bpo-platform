-- Clara Sprachniveau-Gate: B2+ bleibt im Trichter, darunter automatische, freundliche Absage mit offener Tür.
-- Additiv. Gilt NUR für neue Bewerber ab Einschalten (activated_at). Bestand unberührt. Kein Stapelversand
-- (harte Obergrenze pro Lauf + Claras Sende-Budget).

-- Absage-Vorlage im Ton der anderen Absagen, mit Dank + offener Tür.
insert into public.mail_templates (key, subject, body_html, active)
values (
  'reject_language',
  'Deine Bewerbung bei 25hours',
  '<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#222;line-height:1.55;max-width:520px"><p>{{hi}}</p><p>vielen Dank für dein Interesse an 25hours und die Zeit, die du dir für deine Bewerbung genommen hast.</p><p>Für unsere aktuellen Stellen arbeiten wir mit Deutschkenntnissen ab Niveau B2. Nach deinen Angaben passt das diesmal noch nicht ganz.</p><p>Falls du dein Deutsch besser einschätzt, als du angegeben hast: Komm gerne spontan bei uns im Büro vorbei oder bewirb dich einfach erneut mit dem passenden Niveau. Wir freuen uns darauf.</p><p>Alles Gute für deinen weiteren Weg.</p><p>Viele Grüße<br>{{name}}<br><span style="font-size:12px;color:#888">{{disc}}</span></p></div>',
  true
)
on conflict (key) do nothing;

-- Config-Block im bestehenden Clara-Steuerungs-Blob ergänzen, OHNE den Rest zu überschreiben.
-- Standard AUS. activated_at bleibt null bis zum Einschalten in der Steuerung.
update public.app_config
   set value = value || jsonb_build_object(
     'language_gate', jsonb_build_object(
       'enabled', false,
       'min_level', 'B2',
       'activated_at', null,
       'max_new_per_run', 5
     ))
 where key = 'jsr_clara_auto_v1'
   and not (value ? 'language_gate');
