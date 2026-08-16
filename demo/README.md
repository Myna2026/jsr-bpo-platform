# Vorführungs-Fassung — SSF Balkan (Demo)

Eine Kopie der HR-Anwendung mit **fest eingebauten Beispieldaten** statt Datenbank.
Alle Namen, Kunden und Zahlen sind erfunden.

## Starten
`demo/index.html` per Doppelklick im Browser öffnen. Keine Datenbank, keine Anmeldung
(loggt automatisch als „Demo Manager", Rolle Management ein). Internet nötig für die
CDN-Bibliotheken (React/Babel/xlsx). **Speichern ist wirkungslos** — die Daten sind statisch.

## Inhalt
- Firma **SSF Balkan**, 3 Projekte: Nordwind Telekom, Alpina Versicherung, Bergland Reisen.
- **30 erfundene Mitarbeiter** (kosovarische Namen), Positionen Agent bis Projektleiter,
  Skills sales / support / retention.
- Beispieldaten für Cockpit, Mitarbeiter, Schichtplan, Kennzahlen, Abwesenheiten, Bewerber,
  Call-Qualität u. a.

## Technik
- `demo-mock.js` ersetzt `window.supabase` durch eine Attrappe (Beispieldaten + No-Op-Schreiben).
  Es wird nach den CDN-Skripten geladen und überschreibt den echten Client.
- `index.html` ist die unveränderte App-Kopie (nur die Skript-Zeile im `<head>` zeigt auf
  `demo-mock.js` und die lokalen `shared/`-Dateien ohne Build-Version).

Diese Demo ist vollständig vom Live-System getrennt: keine Datenbank, keine Secrets, kein Deploy.
