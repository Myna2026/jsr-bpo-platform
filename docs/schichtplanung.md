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


## Der Schichtplan ist die Abrechnungsgrundlage (HolidayCheck)

Seit der Festlegung vom 2026-09-28 gilt: **abgerechnet wird, was wir laut
Schichtplanung liefern, netto.** Damit ist `shift_assignments` nicht nur
Planung, sondern die Zahl, aus der am Ende die Rechnung wird. Wer im Plan
steht, zählt, unabhängig von Status, Austrittsdatum oder Projektzuweisung.

Die Kette, gerechnet an genau einer Stelle (`supabase/functions/_shared/hc_hours.ts`,
gespiegelt von `HcHoursView` und vom Berichts-Store in `hr.html`):

    net_hours  −  Abwesenheit (employees.absences)  ×  Anteil (jsr_hc_billing_v1)  ×  Satz (project_skills.rate)

Alle drei Stellen müssen dieselbe Zahl liefern. Am 2026-09-29 war das nicht so:
der Berichts-Store prüfte den abrechenbaren Anteil nur auf „größer null" und
ließ Teilanteile voll durchlaufen. Folge: Folie 882,5 h gegen Cockpit 797,9 h
für Sales im September, 84,6 Stunden oder 2.282 Euro Unterschied, je nachdem
wo jemand hinsah. Behoben. **Bei Änderungen an der Rechnung immer alle drei
Stellen anfassen.**

### Bereinigung vom 2026-09-29 und was bewusst stehen blieb

Migration `2026-09-29_hc_plan_bereinigung.sql` hat 14 Schichtzeilen entfernt:
„Portal Testzugang" (10 Schichten, 75 h) sowie je 2 Oktober-Schichten von
Drenusha Leci (Austritt 16.09.) und Ariona Olluri (Austritt 30.09.).

**Bewusst NICHT entfernt: Drenusha Lecis 10 Schichten zwischen dem 17. und
30.09.2026, 75 Stunden netto, rund 1.950 Euro.** Sie stand nach ihrem Austritt
noch im September-Plan. Entscheidung der Geschäftsseite vom 2026-09-29: ein
abgeschlossener Zeitraum wird nicht rückwirkend geändert. Wer sich später
wundert, warum der September Stunden einer bereits ausgetretenen Person
enthält, findet hier die Begründung. Ihre protokollierten Stunden enden
korrekt am 14.09.; die Differenz betrifft nur den Plan.
