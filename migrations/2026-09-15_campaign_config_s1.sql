-- =============================================================================
-- Telefonaktion → wiederverwendbares Werkzeug, SCHNITT 1: Datenmodell generalisieren.
-- REIN ADDITIV. Kein Code liest die neuen Spalten in diesem Schnitt → die laufende
-- Aktion verhält sich GARANTIERT unverändert (phone_link_log ist weiter fest verdrahtet).
-- Die Config wird nur HINTERLEGT, damit Schnitt 2 sie konsumieren kann.
--
-- Config-Schema (config.buttons[]), Vertrag für Schnitt 2:
--   { key      : text            -- wird zu call_leads.status
--     label    : text
--     icon     : text
--     style    : 'amber'|'red'|'green'|'neutral'
--     needs    : 'none'|'date'|'datetime'|'reason'
--     date_label : text          -- Beschriftung des Datumsfelds (z.B. 'Wiedervorlage','Termin')
--     reasons  : [[key,label],…]  -- nur bei needs='reason'
--     effect   : { cv_status         : text|null  -- FREI wählbar; null = CV-Status NICHT ändern
--                  calendar          : bool       -- Kalendereintrag anlegen (braucht Datum/Uhrzeit)
--                  bump_last_worked  : bool } }    -- cvs.last_worked_at = now()
--   (Vierte Wirkung 'Folge-Mail' bewusst NICHT enthalten; kommt später NUR über freigegebene Vorlagen.)
-- Idempotent.
-- =============================================================================

-- Default = die heutige Recruiting-Config. Neue Kampagnen ohne eigene Config verhalten sich damit
-- wie die Recruiting-Aktion; der Builder (Schnitt 3) überschreibt sie je Kampagne.
alter table public.call_campaigns
  add column if not exists config jsonb not null default
  '{"buttons":[
     {"key":"no_answer","label":"Nicht erreicht","icon":"📵","style":"amber","needs":"date","date_label":"Wiedervorlage",
      "effect":{"cv_status":null,"calendar":false,"bump_last_worked":true}},
     {"key":"rejected","label":"Abgesagt","icon":"✗","style":"red","needs":"reason",
      "reasons":[["kein_interesse","Kein Interesse"],["zu_weit","Zu weit weg"],["hat_anderes","Hat schon was anderes"]],
      "effect":{"cv_status":"rejected_by_us","calendar":false,"bump_last_worked":true}},
     {"key":"appointment","label":"Termin","icon":"✅","style":"green","needs":"datetime","date_label":"Termin",
      "effect":{"cv_status":"interview","calendar":true,"bump_last_worked":true}}
   ]}'::jsonb;

alter table public.call_campaigns add column if not exists date_from date;
alter table public.call_campaigns add column if not exists date_to   date;
alter table public.call_campaigns add column if not exists lead_filter jsonb;   -- verwendeter Filter (Doku/Reproduzierbarkeit)

comment on column public.call_campaigns.config is 'Ergebnis-Knöpfe + Wirkungen je Kampagne (Schema siehe Migration 2026-09-15_campaign_config_s1.sql). Schnitt 2 konsumiert es.';

-- Laufende Aktion EXPLIZIT mit der heutigen Recruiting-Config hinterlegen (die Spalten-Default greift nur
-- für neue Zeilen). Wert = 1:1 das aktuelle fest verdrahtete Verhalten → keine Verhaltensänderung.
update public.call_campaigns
   set config = '{"buttons":[
        {"key":"no_answer","label":"Nicht erreicht","icon":"📵","style":"amber","needs":"date","date_label":"Wiedervorlage",
         "effect":{"cv_status":null,"calendar":false,"bump_last_worked":true}},
        {"key":"rejected","label":"Abgesagt","icon":"✗","style":"red","needs":"reason",
         "reasons":[["kein_interesse","Kein Interesse"],["zu_weit","Zu weit weg"],["hat_anderes","Hat schon was anderes"]],
         "effect":{"cv_status":"rejected_by_us","calendar":false,"bump_last_worked":true}},
        {"key":"appointment","label":"Termin","icon":"✅","style":"green","needs":"datetime","date_label":"Termin",
         "effect":{"cv_status":"interview","calendar":true,"bump_last_worked":true}}
      ]}'::jsonb,
       date_from = '2026-09-15',
       lead_filter = '{"phases":["cv_inbound","cv_confirmed"],"min_level":"B2","phone_required":true,
                       "note":"B2+ (Selbstauskunft), Telefon vorhanden; cv_inbound-Start + cv_confirmed-Nachschub"}'::jsonb
 where name = 'Telefonaktion 2026-09-15';

notify pgrst, 'reload schema';
