-- Alten Google-Sheet-Bewerber-Import (gdocsync / syncGoogleDoc) entfernt.
-- Der Weg konnte weniger als der neue CV-Sync (kein Stichtag -> Massen-Import aller Zeilen),
-- dedupte mit abweichender Telefon-Normalisierung und trug einen Zeitplan-Text ohne echte Logik.
--
-- Nur 'jsr_gdoc_sync' lag je in app_config (ueber saveConfigToDB). Die Keys 'jsr_gdoc_last_sync'
-- und 'jsr_gdoc_last_count' waren immer localStorage-only und verschwinden mit dem Browser-Cache;
-- sie stehen hier nur zur Sicherheit mit drin (No-op, falls nicht vorhanden).

delete from app_config
where key in ('jsr_gdoc_sync', 'jsr_gdoc_last_sync', 'jsr_gdoc_last_count');
