-- Vorlage fuer den neuen Buchungslink nach einem geplatzten Termin. Freundlich, ohne Vorwurf:
-- der haeufigste Grund ist ein echtes Hindernis, nicht Desinteresse.
insert into public.mail_templates(key, subject, body_html, active)
values ('noshow_rebook',
 'Neuer Termin bei 25hours: such dir einen aus',
 '<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#222;line-height:1.55;max-width:520px"><p>{{hi}}</p><p>schade, dass es mit unserem Termin nicht geklappt hat. Das passiert, kein Problem.</p><p>Such dir einfach einen neuen Termin aus, der dir besser passt:</p><p><a href="{{link}}" style="display:inline-block;padding:12px 22px;background:#0F5661;color:#fff;text-decoration:none;border-radius:8px;font-weight:700">Neuen Termin wählen</a></p><p style="font-size:13px;color:#666">Falls der Knopf nicht funktioniert, kopiere diesen Link in deinen Browser:<br>{{link}}</p><p>Wenn gerade etwas dazwischenkommt, sag uns kurz Bescheid, dann finden wir einen anderen Weg.</p><p>Viele Grüße<br>{{name}}<br><span style="font-size:12px;color:#888">{{disc}}</span></p></div>',
 true)
on conflict (key) do update set subject=excluded.subject, body_html=excluded.body_html, active=true;

-- Schalter fuer die Automatik (aus by default, wie alle Clara-Phasen).
update public.app_config
   set value = jsonb_set(coalesce(value,'{}'::jsonb), '{noshow_rebook}',
        coalesce(value->'noshow_rebook', '{}'::jsonb) || jsonb_build_object('enabled', coalesce((value->'noshow_rebook'->>'enabled')::boolean,false), 'template','noshow_rebook'), true)
 where key = 'jsr_clara_auto_v1';
select value->'noshow_rebook' as schalter from public.app_config where key='jsr_clara_auto_v1';
