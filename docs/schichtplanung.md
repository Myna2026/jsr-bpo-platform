# Schichtplanung: einfacher Planer + gekapselter Workforce-Planer

> Verbindliche fachliche Vorgabe (ausgelagert aus `CLAUDE.md`, Stand 2026-09-15).
> Bei Konflikten mit bestehendem Code gilt dieses Dokument. Kurzfassung und
> Leitplanken stehen in `CLAUDE.md`.

Seit 2026-07-21 gibt es **zwei** Planungs-Werkzeuge in `hr.html`, die sich
**dieselbe DB-Tabelle** `shift_assignments` (Zeile pro Zelle) teilen — damit
später beides zusammenläuft.

## `SimpleShiftView` (Tab „🗓 Schichtplanung") — das Alltags-Werkzeug
Manuelle, einfache Wochenplanung für **alle** Projekte (Condor, Fabletics, …).
Prinzip „so einfach wie möglich" (siehe Memory `simplicity-first-tools`):
Wochenraster Mo–So, aktuelle KW + letztes Projekt vorausgewählt, Skill nur bei
>1 Skill sichtbar, Klick-Zuweisung mit Auto-Save (kein Speichern-Button),
Standardschicht (meistgenutzte) zuerst, „Vorwoche übernehmen", offene Tage
farblich markiert. **Constraints werden verhindert, nicht gemeldet**: an einem
Tag/mit einer Schicht nicht erlaubte Optionen werden gar nicht erst angeboten.

## `WorkforcePlanningView` (Tab „Workforce (Beta)") — GEKAPSELT
Vollständig erhalten (DB-Anbindung, Forecast-Import, KI-Auto-Planer,
Scoring-Profile), aber im Menü als **„Beta"** markiert und aus dem Alltagsblick
genommen.

- **Warum gekapselt:** Nur für **HolidayCheck Sales** gebaut (Forecast-Upload →
  KI-Stundenverteilung, **ein** Skill). Für einfache Projekte zu komplex.
- **Was er kann:** intraday Coverage-Raster, FC-/FTE-Bedarfsrechnung,
  KI-Autoplanung gegen Forecast, Fairness-/Scoring-Profile.
- **Was fehlt:** sinnvoll nur für 1 Skill/Projekt; Mehrprojekt-/Mehrskill-Sicht
  fehlt. Darum vorerst nicht das Alltags-Tool.
- **Reaktivieren:** Menü-Label zurückbenennen (`Workforce (Beta)` →
  `Planung`) und den `workforce:'beta'`-Eintrag aus `MENU_BADGES_DEFAULT`
  entfernen. Kommt später für die komplexen Projekte (HC Sales/Support,
  Giganetz-Skills) wieder als Erst-Tool dazu.

## Geteilte Prüf-/Config-Logik (kein Duplikat)
Die Constraint- und Schicht-Config-Logik ist als Top-Level-Funktionen
(`shiftEmpDayOk`, `shiftEmpAllowsShift`, `shiftValidTemplates`,
`shiftConfigFor`, `shiftAbsent`) hochgezogen und wird von **beiden** Tools
genutzt. WFPs `canWork`/`validShifts`/`getShifts`/`absent` delegieren dorthin —
Verhalten unverändert. Bei Änderungen an Verfügbarkeits-/Schicht-Regeln immer
**nur diese Top-Level-Funktionen** anfassen, dann gilt es für beide.

