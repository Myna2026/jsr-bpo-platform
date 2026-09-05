-- Clara-Automatik Schnitt 1: Vorlagen-Entwürfe (vom User abgenommen, echte Umlaute) + Steuerung.
-- ALLES standardmäßig AUS (enabled:false) — es sendet nichts automatisch, bis in der Clara-Steuerung
-- scharfgeschaltet. Templates active=true (nutzbar/editierbar). agent_key=clara.
-- Vorlagen-Variablen: {{hi}} Anrede, {{link}} Aktionslink (Phase 1/2), {{name}} Absenderin, {{disc}} Fußzeile.

insert into public.mail_templates (key, agent_key, subject, body_html, active) values
('phase1_eingang','clara','Deine Bewerbung bei 25hours: Profil kurz vervollständigen',
$tpl$<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#222;line-height:1.55;max-width:520px"><p>{{hi}}</p><p>vielen Dank für deine Bewerbung bei 25hours, sie ist bei uns angekommen.</p><p>Damit es für dich schnell weitergeht, vervollständige bitte kurz dein Profil. Das dauert nur wenige Minuten:</p><p><a href="{{link}}" style="display:inline-block;padding:12px 22px;background:#0F5661;color:#fff;text-decoration:none;border-radius:8px;font-weight:700">Profil vervollständigen</a></p><p style="font-size:13px;color:#666">Falls der Knopf nicht funktioniert, kopiere diesen Link in deinen Browser:<br>{{link}}</p><p>Sobald dein Profil vollständig ist, melden wir uns zügig bei dir.</p><p>Viele Grüße<br>{{name}}<br><span style="font-size:12px;color:#888">{{disc}}</span></p></div>$tpl$,
true),

('phase2_termin','clara','Lass uns sprechen: wähle deinen Termin bei 25hours',
$tpl$<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#222;line-height:1.55;max-width:520px"><p>{{hi}}</p><p>wir würden dich gerne kennenlernen. Such dir einfach einen Termin aus, der dir passt, den Rest erledigen wir:</p><p><a href="{{link}}" style="display:inline-block;padding:12px 22px;background:#0F5661;color:#fff;text-decoration:none;border-radius:8px;font-weight:700">Termin wählen</a></p><p style="font-size:13px;color:#666">Falls der Knopf nicht funktioniert, kopiere diesen Link in deinen Browser:<br>{{link}}</p><p>Wir freuen uns auf das Gespräch.</p><p>Viele Grüße<br>{{name}}<br><span style="font-size:12px;color:#888">{{disc}}</span></p></div>$tpl$,
true),

('reject_by_us','clara','Deine Bewerbung bei 25hours',
$tpl$<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#222;line-height:1.55;max-width:520px"><p>{{hi}}</p><p>vielen Dank für dein Interesse an 25hours und die Zeit, die du dir für deine Bewerbung genommen hast.</p><p>Wir haben uns diesmal für andere entschieden. Über eine spätere Bewerbung freuen wir uns jederzeit.</p><p>Alles Gute für deinen weiteren Weg.</p><p>Viele Grüße<br>{{name}}<br><span style="font-size:12px;color:#888">{{disc}}</span></p></div>$tpl$,
true),

('reject_by_client','clara','Deine Bewerbung bei 25hours',
$tpl$<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#222;line-height:1.55;max-width:520px"><p>{{hi}}</p><p>vielen Dank für dein Interesse und die Zeit, die du in deine Bewerbung gesteckt hast.</p><p>Für das konkrete Projekt hat es diesmal leider nicht gepasst. Das sagt nichts über deine Qualifikation, die Anforderungen waren einfach sehr spezifisch.</p><p>Wir behalten dein Profil gerne für andere Projekte im Blick und melden uns, wenn etwas Passendes dabei ist.</p><p>Viele Grüße<br>{{name}}<br><span style="font-size:12px;color:#888">{{disc}}</span></p></div>$tpl$,
true),

('no_contact','clara','Wir haben dich leider nicht erreicht: 25hours',
$tpl$<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#222;line-height:1.55;max-width:520px"><p>{{hi}}</p><p>wir haben mehrfach versucht, dich zu deiner Bewerbung bei 25hours zu erreichen, leider ohne Erfolg.</p><p>Falls du weiterhin Interesse hast, melde dich einfach kurz bei uns, dann machen wir sofort weiter. Meldest du dich nicht, gehen wir davon aus, dass sich die Sache erledigt hat.</p><p>Viele Grüße<br>{{name}}<br><span style="font-size:12px;color:#888">{{disc}}</span></p></div>$tpl$,
true)
on conflict (key) do update set subject=excluded.subject, body_html=excluded.body_html, agent_key=excluded.agent_key, active=excluded.active, updated_at=now();

-- Steuerung: alle Schalter AUS, Fenster in Werktagen (in der Clara-Steuerung ohne Code editierbar).
-- do nothing: bestehende Konfiguration/Schalter NICHT überschreiben.
insert into public.app_config (key, value) values ('jsr_clara_auto_v1', $cfg$
{
  "sender_key": "clara",
  "reject_delay_hours": 48,
  "windows": { "reminder_workdays": 2, "handover_workdays": 3, "hard_cap_workdays": 5 },
  "phases": {
    "phase1": { "enabled": false, "status": "cv_inbound",   "template": "phase1_eingang" },
    "phase2": { "enabled": false, "status": "cv_confirmed", "template": "phase2_termin" }
  },
  "rejects": {
    "rejected_by_us":     { "enabled": false, "template": "reject_by_us" },
    "rejected_by_client": { "enabled": false, "template": "reject_by_client" },
    "no_contact":         { "enabled": false, "template": "no_contact" }
  }
}
$cfg$::jsonb)
on conflict (key) do nothing;
