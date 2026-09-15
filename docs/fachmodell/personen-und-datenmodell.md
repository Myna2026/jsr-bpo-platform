# Personen- und Datenmodell

> Verbindliche fachliche Vorgabe (ausgelagert aus `CLAUDE.md`, Stand 2026-09-15).
> Bei Konflikten mit bestehendem Code gilt dieses Dokument. Kurzfassung und
> Leitplanken stehen in `CLAUDE.md`.

## Datenmodell: Mitarbeiter, Projekte, Zuweisungen

Diese Sektion ist verbindliche fachliche Vorgabe für alle Änderungen an
`hr.html`, `mitarbeiter.html`, `client.html`. Bei Konflikten mit bestehendem
Code gilt diese Sektion.

### Positionen und Kategorien
Jeder Mitarbeiter hat eine `position`. Aus der `position` wird die Kategorie
abgeleitet (Single Source of Truth: nicht doppelt speichern).

| position      | category |
|---------------|----------|
| Agent         | agent    |
| Senior Agent  | agent    |
| ASP           | agent    |
| Supervisor    | agent    |
| Teamleiter    | overhead |
| Trainer       | overhead |
| QM            | overhead |
| Projektleiter | overhead |
| HR            | admin    |
| Management    | admin    |
| Finance       | admin    |
| IT            | admin    |

Neue Positionen müssen in dieser Liste ergänzt werden, sonst werden sie vom
System abgelehnt.

### Projekte und Skills
Ein Projekt hat einen oder mehrere Skills (z. B. Projekt „Holidaycheck" mit
Skills „Support" und „Sales"). Skills sind eine Eigenschaft des Projekts,
nicht des Mitarbeiters.

### Projektzuweisungen
Die Zuweisung Mitarbeiter ↔ Projekt ↔ Skill ist die operative Kernstruktur
(KPIs, Schichten, Auswertungen laufen darüber).

Datenstruktur:

```
project_assignments: [
  { employee_id, project_id, skill, start_date, end_date }
]
```

`end_date: null` bedeutet: aktuell laufende Zuweisung.

Bei einem Wechsel wird die alte Zuweisung geschlossen (`end_date` gesetzt)
und eine neue mit dem neuen Start angelegt. Alte Zuweisungen werden nie
überschrieben oder gelöscht — die Historie bleibt vollständig erhalten.

### Validierungsregeln pro Kategorie
- **Agent** (`Agent`, `Senior Agent`, `ASP`): Genau eine offene Zuweisung
  (`end_date: null`). Pflichtfeld — ein Agent ohne aktive Zuweisung ist ein
  Fehler.
- **Overhead** (`Teamleiter`, `Trainer`, `QM`, `Projektleiter`): Mindestens
  eine offene Zuweisung. Mehrere offene Zuweisungen erlaubt — sowohl mehrere
  Skills auf demselben Projekt als auch über mehrere Projekte hinweg.
  Hintergrund: Auslastung bei kleinen Projekten.
- **Admin** (`HR`, `Management`, `Finance`, `IT`): Keine Projektzuweisung.
  Diese Mitarbeiter sind übergeordnet und nicht projektbezogen tätig.
  Auswertungen wie „Mitarbeiter auf Projekt X" zählen sie nicht mit.

### CV-Skills vs. Projekt-Skill (NICHT verwechseln)
Es gibt zwei verschiedene Skill-Felder mit unterschiedlicher Bedeutung:

- **`cv_skills`** (Array, am Mitarbeiter/Bewerber): Selbstauskunft auf dem
  CV, mehrere möglich („was kann diese Person grundsätzlich"). Dient
  Profil-Auswertungen. Ändert sich selten.
- **Projekt-Skill** (Teil der `project_assignments`-Zeile): Der Skill, mit
  dem die Person aktuell auf einem konkreten Projekt arbeitet. Operative
  Wahrheit für KPIs und Schichten.

Diese Felder sind nie austauschbar. Kein Fallback von einem aufs andere.
Wenn ein Mitarbeiter keine aktive Projektzuweisung hat, hat er auch keinen
Projekt-Skill — Punkt. Für operative Auswertungen wird ausschließlich der
Skill aus der Projektzuweisung verwendet, nie der CV-Skill.

### Storage-Key (offene Migrationsfrage)
Mitarbeiterdaten werden heute in zwei parallelen LocalStorage-Keys gehalten
(`jsr_employees_v1` und `jsr_emp_v3`), die unterschiedliche Module
unterschiedlich lesen/schreiben. Künftiger Master-Store: `jsr_emp_v3`. Die
Migration v1 → v3 ist ein eigenes Vorhaben, das vor dem Produktivgang
abgeschlossen sein muss.

## Master-Feldnamen und Strukturen

Für wiederkehrende fachliche Felder gelten die folgenden Master-Namen
verbindlich. Alte Schreibweisen werden vor dem Produktivgang entfernt
(siehe „Feldnamen-Migration" in den offenen technischen Schulden).

### Bankdaten
Strukturierter Block am Mitarbeiter:

```
bank: {
  name: string,    // z. B. "Sparkasse Köln"
  iban: string,
  bic: string
}
```

Status: weiches Pflichtfeld. Beim Anlegen oder bei Status-Wechsel zu
`contract` blockiert fehlende Bankverbindung den Flow nicht. Das System
markiert Personen mit unvollständigen Bankdaten sichtbar (Warn-Indikator,
Übersichts-Liste „Bankdaten fehlen"). Spätestens vor der ersten
Lohnzahlung ist die Vervollständigung Pflicht.

Abgeschafft werden: `bank_account`, `bank_iban` (als Einzelfelder),
`bank_name` (als Einzelfeld).

### Ausweis-Nummer
Master: `id_number`. Abgeschafft wird: `id_card`.

### Position
Master: `position`. Abgeschafft wird: `role` (aktuell in `client.html`).
Die Position-zu-Kategorie-Zuordnung steht in der Sektion „Datenmodell".

### Vertragsdaten
Strukturierter Block am Mitarbeiter:

```
contract: {
  signed_at: date,        // Vertragsunterschrift
  start: date,            // Vertraglicher Beginn = Bezahlungsbeginn
  end: date | null,       // null = unbefristet (läuft bis Kündigung)
                          // Datum = befristet bis dahin
  title: string,          // Position laut Vertrag
  project: string         // Initial-Projekt laut Vertrag
}
```

`contract.start` ist die einzige Quelle der Wahrheit für „Vertragsbeginn
/ Eintrittsdatum / Bezahlungsbeginn".

Die Vertragsdauer ergibt sich aus `start` und `end` — kein separates
`duration_months`-Feld.

Abgeschafft werden: Alle flachen Felder mit `contract_`-Präfix
(`contract_start`, `contract_end`, `contract_title`, `contract_project`,
`contract_duration`), die Alternativ-Namen `hire_date` und `start_date`
für den Vertragsbeginn sowie `contract.start_date`/`contract.end_date`
(Master ist `contract.start`/`contract.end`).

### Anpassung im Personen-Modell
Die im Personen-Modell-Manifest weiter unten genannten flachen
Datumsfelder (`contract_signed_at`, `contract_start`) werden ersetzt
durch die verschachtelten Master-Namen `contract.signed_at` und
`contract.start`. Die fachliche Bedeutung bleibt identisch.

## Personen-Modell: CV, Mitarbeiter, Lebenszyklus

Diese Sektion ist verbindliche fachliche Vorgabe für alle Änderungen an
`hr.html`, `mitarbeiter.html`, `client.html`. Sie ergänzt die
Datenmodell-Sektion.

### Eine Person, eine ID, ein Lebenszyklus
Eine Person ist ein einziger Datensatz mit einer stabilen ID, die nie
wechselt. Es gibt keine getrennten Datenstrukturen für CV und Mitarbeiter
und kein Umkopieren beim Statuswechsel. Eine Person wechselt im Laufe
ihres Lebenszyklus nur ihren `status`. Daten bleiben dauerhaft mit
derselben ID verknüpft.

### Wege ins System
Zwei mögliche Einstiegspunkte:

- **Weg A — CV-Funnel:** Person wird mit Status `cv_inbound` angelegt.
  Durchläuft die CV-Phasen. Endet entweder in einem `rejected_*` /
  `blacklist`-Status oder erreicht `contract` und wird Mitarbeiter.
- **Weg B — Direkteinstellung:** Person wird direkt mit Status `contract`
  angelegt. Kein CV-Funnel-Vorlauf. Begründung: Sondersituationen, in
  denen der Funnel-Prozess unnötig wäre und Team-Zeit kosten würde.
  Pflichtfelder beim Anlegen: `contract_signed_at`, `contract_start`,
  `staff_number`.

Egal welcher Weg: Sobald eine Person Mitarbeiter wird, geschieht das
immer über Status `contract`.

### Status-Werte (19 finale Stati)

**CV-Funnel-Phasen** (Person ist Bewerber):
- `cv_inbound` — CV eingegangen
- `cv_accepted` — CV akzeptiert
- `cv_confirmed` — CV angelegt und bestätigt
- `invited` — Einladung zum Gespräch
- `interview` — Vorstellungsgespräch
- `selection1` — Erste Auswahlrunde
- `selection2` — Zweite Auswahlrunde

**Mitarbeiter-Phasen** (Person ist Mitarbeiter):
- `contract` — Vertrag unterschrieben. Person ist offiziell Mitarbeiter,
  planbar und schichtbar, aber noch nicht aktiv. Bezahlung beginnt erst
  am `contract_start`, nicht bei Vertragsunterschrift.
- `training_planned` — Schulung geplant
- `training` — Schulung läuft (bereits in Bezahlung)
- `active` — Aktiv auf Projekt mit Skill (produktiv)
- `inactive` — Pausiert (Elternzeit, Langzeitkrankheit etc.)

**Sonderfall:**
- `parking` — Bewerber „geparkt" für spätere Wiedervorlage

**Terminale Endzustände** (kein Weiter):
- `rejected_by_us` — Wir lehnen ab
- `rejected_by_employee` — Bewerber zieht zurück
- `rejected_by_client` — Auftraggeber lehnt ab
- `blacklist` — Auf Blacklist
- `terminated_by_us` — Vom AG gekündigt
- `terminated_by_employee` — Vom MA gekündigt

### Wichtige Datumsfelder
- `cv_received_at` — Eingang ins System (auch bei Direkteinstellung
  gesetzt, dann = Anlagedatum)
- `contract_signed_at` — Vertragsunterschrift
- `contract_start` — Vertraglicher Beginn = Bezahlungsbeginn. Kann in der
  Zukunft liegen (Beispiel: Unterschrift im Juni, Start im August)
- `staff_number` — Fortlaufende Mitarbeiternummer, vergeben beim Übergang
  in Status `contract`
- `employment_end` — Datum bei Status `terminated_*` oder `inactive`

### Status-Übergänge
Alle Übergänge sind manuell durchs HR-Team gesteuert. Das System trifft
keine automatischen Statuswechsel.

**Harte Vorbedingung:**
- `training_planned` und `training` können nur gesetzt werden, wenn die
  Person bereits in `contract` oder einer späteren Mitarbeiter-Phase ist.
  Ohne Vertrag keine Schulung. Das System muss diese Bedingung
  durchsetzen.

### Keine Kopiervorgänge
Beim Statuswechsel werden keine Daten zwischen Datensätzen kopiert. Die
`promoteToEmployee`-Logik aus dem aktuellen Code (`hr.html:23489`) wird
abgeschafft — stattdessen wird beim Übergang zu `contract` nur der Status
gesetzt, `contract_signed_at`, `contract_start` und `staff_number` werden
befüllt. Die Person bleibt dieselbe.

