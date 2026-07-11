# CLAUDE.md — tourism-leads / JSR BPO Intelligence Platform

## Was die Anwendung macht
Ursprünglich DACH Tourismus-Lead-Management für Call-Center (siehe `README.md`),
inzwischen zu einer breiteren **BPO Intelligence Platform** gewachsen. Mehrere
Geschäftsmodule (HR, Mitarbeiter, Client, Stempel, Leads)
liegen als monolithische HTML-Dateien im `frontend/`-Ordner. Buchhaltung und
Belege sind in das eigene Repo tive-finance ausgelagert (Vercel:
tive-finance.vercel.app).

## Modul-Scope (wichtig)
- **Kernmodule** (Fokus, hier wird weiterentwickelt):
  - `frontend/hr.html`
  - `frontend/mitarbeiter.html`
  - `frontend/client.html`
- **Nachrangig**: `leads.html`, `stempel.html`,
  Nebenseiten (`bewerber.html`, `index.html`, `payslip_preview.html`,
  `setup.html`, `showcase.html`, `dummy_loader.html`).

**Hintergrund:** Vom User am 2026-05-26 explizit als langfristiger Scope
festgelegt. Die `README.md` beschreibt nur den ursprünglichen
Tourism-Leads-Teil und spiegelt diese Priorisierung nicht wider — bei
Konflikten gilt CLAUDE.md.

**Verhaltensregeln:**
- Bei vagen oder mehrdeutigen Anfragen kurz nachfragen, statt stillschweigend
  ein Modul anzunehmen. Nur wenn die Anfrage einen eindeutigen inhaltlichen
  Hinweis enthält (z. B. „Bewerber", „Schicht", „Kunde"), ohne Rückfrage
  darauf basieren.
- Bei nachrangigen Modulen vorsichtiger mit umfangreichen Änderungen sein;
  im Zweifel vorher klären, ob sich der Aufwand lohnt.
- Architektur- und übergreifende Vorschläge primär an `hr.html`,
  `mitarbeiter.html`, `client.html` ausrichten — nicht an Modulen, die
  ausgekapselt oder nachrangig sind.

- **Ausgelagert in eigenes Repo** (nicht mehr Teil des CRM):
  - Buchhaltung und Belege leben im Repo `tive-finance`
  - Live unter https://tive-finance.vercel.app/
  - Verlinkt aus dem CRM-Launcher (`frontend/index.html`) als
    externe Kacheln, die in neuem Tab aufgehen

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

## Urlaubs-Modell

Diese Sektion ist verbindliche fachliche Vorgabe für alle Änderungen an
`hr.html` und `mitarbeiter.html` rund um Urlaubsanspruch, Urlaubsanträge
und Urlaubsverbrauch.

### Urlaubsanspruch
Der jährliche Urlaubsanspruch wird zentral im Admin konfiguriert und gilt
für alle Mitarbeiter, außer wo manuell überschrieben.

**Standard-Regel (Admin):**
- **Startjahr**: 18 Tage anteilig nach Eintrittsmonat. Berechnung:
  18 × (Resttage im Jahr ab Eintritt) / 365, alternativ vereinfacht über
  volle Restmonate.
- **Folgejahre**: 20 Tage voll.

Beide Werte sind im Admin durch das Management konfigurierbar.

**Manueller Override durch Management:**
Für Einzelfälle (Sondervereinbarungen, lange Betriebszugehörigkeit, etc.)
kann das Management den Anspruch pro Mitarbeiter überschreiben. Der
manuelle Wert ersetzt komplett die Standard-Regel (kein Bonus oben drauf).

Beim Setzen wählt das Management eine Gültigkeit:
- **1 Jahr**: Override gilt nur für ein Kalenderjahr, danach greift
  wieder die Standard-Regel.
- **Dauerhaft**: Override gilt bis jemand ihn wieder ändert.

Datenmodell (vereinfacht):

```
vacation: {
  override: {
    days: int,
    scope: 'single_year' | 'permanent',
    valid_year: int | null     // bei single_year: welches Jahr
  } | null                     // null = Standard-Regel greift
}
```

### Urlaubsantragsverfahren

**Antragsweg:**
Der Mitarbeiter beantragt Urlaub in seinem Login unter `mitarbeiter.html`.
Der Antrag taucht in `hr.html` im Tab „Urlaubsanträge" auf und wird dort
vom Management entschieden.

**Antragsinhalt:**
- Von-Bis-Datum (Pflicht)
- Optionale Notiz / Begründung

**Mögliche Management-Entscheidungen:**
- **Grün — Freigabe**: Antrag wird unverändert genehmigt.
- **Gelb — Anpassung**: Management ändert Zeitraum oder Tageszahl und
  gibt frei. Der Mitarbeiter muss die Anpassung in seinem Account
  bestätigen oder ablehnen. Erst bei Bestätigung gilt der angepasste
  Antrag als genehmigt.
- **Rot — Ablehnung**: Antrag wird abgelehnt.

Mitarbeiter sieht das Ergebnis als Ampel-Rückmeldung in seinem Account.

**Unbeantwortete Anpassungen (Gelb):**
Wenn der Mitarbeiter eine Anpassung über längere Zeit nicht bestätigt
oder ablehnt, erhält das Management einen Reminder mit Sichtbarkeit auf
den hängenden Antrag. Keine automatischen Statuswechsel — Management
entscheidet manuell, wie weiter verfahren wird.

### Urlaubsverbrauch und Planungs-Logik

**Zweistufiger Verbrauch:**
- **Reserviert**: Freigegebene zukünftige Urlaubstage (noch nicht
  erreicht).
- **Verbraucht**: Bereits vergangene Urlaubstage.

Tage werden erst beim tatsächlichen Eintreten von „reserviert" zu
„verbraucht" umgebucht.

**Planungs-Sperre:**
Es kann nie mehr Urlaub geplant werden, als theoretisch verfügbar ist —
auch wenn die Tage noch nicht aktiv verbraucht sind.

Formel:
```
planbar_verbleibend = effective_quota - reserved_days - used_days
```

Beispiel: Bei 18 Tagen Anspruch und 10 reservierten Tagen im August
können maximal noch 8 Tage für Oktober beantragt werden — nicht 10.

### Halbe Urlaubstage
Halbe Tage sind erlaubt, aber nur als glatt halb (Vormittag oder
Nachmittag). Kein freies Stückeln (0,3 oder 0,7 Tage nicht möglich).

### Integration in andere Systembereiche
Nach Freigabe (Grün oder bestätigtes Gelb) wird der Urlaub automatisch
in alle relevanten Bereiche übernommen:

- **Workforce-Planung**: Person ist im freigegebenen Zeitraum als „im
  Urlaub" markiert.
- **Gehaltsabrechnung**: berücksichtigt Urlaubstage entsprechend.
- **Auswertungen**: verbrauchte und verbleibende Tage werden automatisch
  fortgeschrieben.

Keine doppelte Erfassung an anderer Stelle — die Urlaubs-Datensätze sind
die Single Source of Truth.

### Jahresübergänge und Sonderfälle

**Resturlaub am Jahresende:**
Nicht verbrauchte Tage werden ins Folgejahr übertragen und müssen bis
spätestens 31. März des Folgejahres genommen werden. Danach verfallen
sie ersatzlos. Diese Regel greift im laufenden Beschäftigungsverhältnis
— bei Kündigung gilt eine eigene Regel (siehe unten).

**Krankheit während Urlaub:**
- **Standard**: Krankheitstage mit ärztlichem Attest werden vom Urlaub
  abgezogen und gutgeschrieben (Person kann sie später nachholen).
- **Management-Sonderregel**: Im Einzelfall kann das Management
  entscheiden, dass die Urlaubstage trotzdem als Urlaub gewertet werden.
  Diese Entscheidung muss aktiv getroffen werden — Standard ist immer
  Gutschrift.

### Kündigung und Urlaub

**Zu viel verbrauchter Urlaub:**
Wenn der Mitarbeiter bei Austritt mehr Urlaub genommen hat, als ihm
anteilig zustand, wird die Differenz vom letzten Gehalt abgezogen.

**Resturlaub bei Kündigung:**
Verbleibender Urlaub wird durch Freistellung vor dem Austrittstag
abgebaut — keine Auszahlung als Standard.

Diese Regel greift auch dann, wenn der Resturlaub aus dem Vorjahr stammt
und die normale 31.03.-Verfallsfrist betroffen wäre: Bei Kündigung wird
immer freigestellt, nicht verfallen lassen.

**Ausnahme:**
Auszahlung von Resturlaub ist nur als manuelle Einzelfallentscheidung
des Managements möglich (z. B. wenn die Kündigungsfrist zu kurz für
eine sinnvolle Freistellung ist). Kein automatischer Mechanismus.

## Abwesenheits-Modell

Diese Sektion ist verbindliche fachliche Vorgabe für alle Änderungen an
Abwesenheits-, Krankheits- und Verfügbarkeits-Logik in `hr.html` und
`mitarbeiter.html`. Sie ergänzt das Urlaubs-Modell um die
nicht-urlaubsbezogenen Abwesenheiten.

### Grundprinzip
Es gibt drei Abwesenheits-Typen, alle leben einheitlich in der Liste
`employee.absences[]` mit Discriminator-Feld `type`:

| Typ                              | Wer trägt ein         | Bezahlt? | Wirkung auf Soll-Stunden | Wirkung auf Gehalt |
|----------------------------------|-----------------------|----------|--------------------------|--------------------|
| `vacation` (Bezahlter Urlaub)    | Mitarbeiter (Antrag)  | Ja       | Soll erfüllt             | Voll bezahlt       |
| `unpaid` (Unbezahlte Abwesenheit)| Mitarbeiter ODER HR   | Nein     | Soll reduziert           | Anteilig gekürzt   |
| `sick` (Krankheit)               | HR/Management         | Ja       | Soll erfüllt             | Voll bezahlt       |

Für jeden Tag, an dem ein Mitarbeiter abwesend ist, existiert genau ein
Eintrag im `absences[]`-Array — egal welcher Typ.

### Bezahlter Urlaub (`type:'vacation'`)
Wird durch das Urlaubsantragsverfahren beantragt (siehe Sektion
„Urlaubs-Modell"). Die Details dort gelten weiterhin: Mitarbeiter
beantragt im `mitarbeiter.html`, Management entscheidet im `hr.html`
(Grün/Gelb/Rot), zweistufiger Verbrauch (reserviert/verbraucht),
Planungs-Sperre.

Nach Freigabe wird ein Eintrag mit `type:'vacation'`, `paid:true`,
`approved:true` in `employee.absences[]` geschrieben.

### Unbezahlte Abwesenheit (`type:'unpaid'`)
Es gibt zwei mögliche Anlässe, beide enden im gleichen Datensatz-Typ:

- **Unbezahlter Urlaub auf Antrag des Mitarbeiters**: Der Mitarbeiter
  beantragt im `mitarbeiter.html` (ergänzendes Antragsformular zur
  Urlaubsbeantragung, Auswahl bezahlt/unbezahlt). Workflow analog zum
  Urlaubsantrag (Grün/Gelb/Rot durchs Management).
- **Sonstige unbezahlte Abwesenheit, eingetragen durch HR/Management**:
  Z. B. unentschuldigtes Fehlen, Sonderfälle ohne Lohnfortzahlung,
  Behördentermine. Kein Antrag, sondern direkter Eintrag durch HR.

Beide Wege schreiben einen Eintrag `type:'unpaid'`, `paid:false` in
`employee.absences[]`. Wirkung ist identisch (Soll und Gehalt werden
reduziert), nur der Anlass und das Eintrags-Verfahren unterscheiden sich.

### Krankheit (`type:'sick'`)
Wird von HR/Management eingetragen, nicht beantragt. Der typische Ablauf
bei euch (laut interner Wissensdatenbank `mitarbeiter.html:620-621`):
Mitarbeiter ruft am Krankheitstag bis 8:30 Uhr an, HR trägt es ein. Ab
3 Tagen Krankschreibung wird ein ärztliches Attest verlangt.

Eintrag: `type:'sick'`, `paid:true` in `employee.absences[]`.
Standardmäßig immer bezahlt (Lohnfortzahlung).

### Wirkung auf Soll-/Ist-Stunden
Im Soll-/Ist-Stunden-Konto (siehe Sektion „Schichtmodell") werden
Abwesenheiten so verbucht:

- **`vacation` und `sick`**: Soll-Stunden des Tages werden als erfüllt
  gewertet. Tag fließt voll ins Soll und Ist gleichermaßen, kein
  Fehlstundenaufbau.
- **`unpaid`**: Soll-Stunden des Tages werden reduziert (Person hatte
  an dem Tag kein Soll mehr). Damit entstehen keine Fehlstunden, aber
  der Monatsbeitrag zur Sollarbeit sinkt.

### Wirkung auf Gehaltsberechnung
- **`vacation` und `sick`**: Voll bezahlt. Keine Kürzung des
  Monatsgehalts.
- **`unpaid`**: Anteilig gekürzt. Pro abwesenden Tag wird das
  Monatsgehalt durch die regulären Arbeitstage des Monats geteilt und
  abgezogen.

Die genaue Berechnungsformel und Lohnabrechnungs-Anbindung ist Teil der
noch zu prüfenden Gehalts-Verknüpfung (siehe „Offene technische
Schulden").

### Integration mit Workforce-Planung
Sobald ein Eintrag in `employee.absences[]` für einen Tag existiert, ist
die Person an diesem Tag nicht planbar. Das System darf keinen
Schichten/Projekt-Slot mehr für sie reservieren.

Der bestehende Code in `hr.html:5703-5715` prüft das typ-agnostisch über
einen `isAbsent`-Boolean — das heißt: Workforce unterscheidet nicht
zwischen Krankheit, Urlaub oder unbezahlt. Aus Workforce-Sicht ist
„abwesend = abwesend, Produktivstunden = 0, Umsatz = 0". Das ist korrekt
und bleibt so.

### Datenstruktur

```
employee.absences: [
  {
    type: 'vacation' | 'unpaid' | 'sick',
    from: 'YYYY-MM-DD',
    to: 'YYYY-MM-DD',
    days: int,           // Anzahl Werktage im Zeitraum
    paid: boolean,       // true für vacation/sick, false für unpaid
    approved: boolean,   // Genehmigt durchs Management
    note: string         // Optional: Begründung
  }
]
```

Persistenz: zusammen mit dem Mitarbeiter-Datensatz in `jsr_emp_v3`.
Anträge (vor Genehmigung) liegen in `jsr_vacation_requests_v1`.

## Gehaltsmodell

Diese Sektion ist verbindliche fachliche Vorgabe für alle Änderungen an
Gehalts-, Bonus- und Auszahlungs-Logik in `hr.html` und `mitarbeiter.html`.

### Grundprinzip
Jeder Mitarbeiter hat ein festes Monatsgehalt in Euro. Dieser Wert bleibt
statisch und ist unabhängig davon, wie viele Arbeitstage der konkrete
Monat hat.

Der Stundenlohn ist kein eigenständig gepflegtes Feld, sondern ergibt
sich rechnerisch:

```
stundenlohn = monatsgehalt / arbeitsstunden_des_monats
```

Dadurch variiert der Stundenlohn zwischen Monaten (Februar wegen
kürzerer Arbeitszeit höher als Januar), das Monatsgehalt bleibt aber
konstant. Das aktuell im Code existierende Feld `hourly_rate` als
gespeicherte Größe widerspricht diesem Prinzip — siehe Hinweise zur
Feldnamen-Migration.

### Bonus-Typen
Es gibt vier mögliche Bonus-Arten. Welche Boni ein konkreter Mitarbeiter
bekommt, ergibt sich pragmatisch aus der Pflege: gepflegt/zugeordnet →
wird ausgezahlt, nicht gepflegt → kein Bonus. Keine starre
„Bonus-Berechtigung" pro Person.

**1. Pauschal-Bonus**
Manager trägt manuell einen festen Eurobetrag ein (z. B. 250 €). Frei
pro Mitarbeiter und Monat.

**2. KPI-/Leistungs-Bonus**
Manager trägt manuell einen Wert basierend auf Performance ein. Auch
hier manuelle Eingabe pro Mitarbeiter und Monat, keine automatische
Berechnung.

**3. Referral-Bonus**
Mitarbeiter A wirbt Bewerber B an. Wenn B Mitarbeiter wird und produktiv
anfängt, bekommt A Geld.

- Gesamtbetrag wird vom Management pro Einzelfall manuell festgelegt
  (kein globaler Standardbetrag).
- Aufteilung in zwei Tranchen, prozentuale Verteilung im Admin für alle
  Referrals einheitlich konfigurierbar (Default 50/50, Persistenz
  `jsr_referral_config_v1`).
- Fälligkeit zählt ab Status `active` des Geworbenen, **nicht** ab
  Vertragsunterschrift:
  - **Tranche 1**: Default 1 Monat nach `active`
  - **Tranche 2**: Default 4 Monate nach `active`
  - Beide Zeiträume im Admin konfigurierbar.
- Bedingung für jede Tranche: Der Geworbene muss zum Fälligkeitszeitpunkt
  noch Mitarbeiter sein. Wird er vorher `terminated_*`, entfällt die
  jeweilige Tranche.
- Konsequenz: Wenn der Geworbene nie `active` wird (z. B.
  Vertragsunterschrift, aber Abbruch in Training), bekommt der Werber
  nichts — auch nicht Tranche 1. Das ist gewollt: Der Bonus honoriert
  produktive Vermittlung, nicht nur Unterschriften.

**4. Drehrad-Gewinn**
Mitarbeiter kann am monatlichen Drehrad gewinnen. Das System ordnet
Gewinner automatisch zu. Keine manuelle Pflege durchs Management nötig.

### Auszahlungsrhythmus
**Gehalt:** Monatlich, am 15. des Folgemonats. Beispiel: Juni-Gehalt
wird am 15. Juli ausgezahlt.

**Boni:** Werden automatisch in die Gehaltsabrechnung des Folgemonats
integriert, sobald sie laut System fällig sind.

- Pauschal-/KPI-Bonus: vom Management in den ersten zwei Wochen des
  Folgemonats für den vergangenen Monat gepflegt (z. B. Juli-Wochen 1+2
  für Juni).
- Referral-Tranchen: automatisch fällig, wenn die zeitliche Bedingung
  erreicht ist.
- Drehrad-Gewinn: automatisch fällig im Monat des Gewinns.

Es gibt keine separate Bonus-Auszahlung außerhalb des regulären
Lohnlaufs. Alles läuft am 15. des Folgemonats über die normale
Gehaltsabrechnung.

### Darstellung auf der Gehaltsabrechnung
Jede Bonus-Art erscheint als eigene Zeile auf der Lohnabrechnung —
transparent und nachvollziehbar für den Mitarbeiter:

```
Lohnabrechnung Juni 2026 (Auszahlung 15.07.2026)
─────────────────────────────────────────────────
Fix-Gehalt                              1.000,00 €
Bonus pauschal                            250,00 €
Bonus KPI                                 150,00 €
Referral Tranche 1                        500,00 €
Drehrad-Gewinn                             50,00 €
─────────────────────────────────────────────────
Summe brutto                            1.950,00 €
```

Boni, die in einem Monat 0 € sind, können entweder weggelassen oder mit
0 € sichtbar gemacht werden — Darstellungs-Detail.

### Offene technische Lücke
Das aktuelle Feld `hourly_rate` am Mitarbeiter widerspricht der
ableitenden Logik („Stundenlohn ergibt sich aus Monatsgehalt") und
sollte im Rahmen der Feldnamen-Migration entweder entfernt oder als
rein abgeleiteter Anzeigewert ausgewiesen werden.

## Deployment & Git-Workflow

### Deployment
- **Frontend**: deployt automatisch über **Vercel** aus dem GitHub-Repo
  (`github.com/Myna2026/jsr-bpo-platform`). Jeder Push auf `main` löst
  sofort ein Live-Deployment aus — Branch entsprechend vorsichtig behandeln.
  Vercel-Konfiguration liegt im `.vercel/`-Ordner.
- **Backend**: läuft separat (nicht auf Vercel). Eigene Infrastruktur,
  unabhängiger Lifecycle.

### Git-Push
- Vor jedem `git push`: erst `git status` und `git diff` (bzw.
  `git diff origin/main...HEAD` für bereits committete Änderungen) zeigen
  und auf ausdrückliche Bestätigung des Users warten. Erst nach „ok"/„push"
  tatsächlich pushen.
- Commits werden nur auf explizite Aufforderung erstellt.
- User pusht in der Regel selbst über **GitHub Desktop** (Repo-Pfad:
  `/Users/sehring/Desktop/Claude_Code/BPOX/tourism-leads`). Wenn Push via
  Terminal nicht funktioniert (Credentials-Fehler), den User darauf
  hinweisen, dass er stattdessen über GitHub Desktop pushen kann.

### Secrets
- Niemals `.env`-Dateien oder Secrets committen. `backend/.env` ist in der
  `.gitignore`. Betrifft u. a.: API-Keys (`APOLLO_API_KEY`,
  `HUNTER_API_KEY`, `PROXYCURL_API_KEY`, `ANTHROPIC_API_KEY`,
  `SECRET_KEY`), Datenbank-Passwörter, Vercel-Tokens.
- Beim Staging gezielt Dateien benennen, nicht `git add -A` / `git add .`
  verwenden.
- Vor jedem Stagen: kurz gegen `.gitignore` prüfen.
- Falls eine `.env.example` benötigt wird: nur Platzhalter, keine echten
  Werte.

## Belege-Auskapselung

VOLLSTÄNDIG ERLEDIGT (Juni 2026).

1. Die zuvor in buchhaltung.html und belege.html enthaltenen
   Module wurden in das eigenständige Repo `tive-finance`
   ausgelagert. Live unter https://tive-finance.vercel.app/.

2. Der zuvor in hr.html eingebettete InvoiceView-Block
   (Buchhaltung/Belege-Komponente, ~978 Zeilen) wurde
   komplett entfernt. Die Komponente war toter Code
   ohne Mount-Punkt und ist damit ohne Funktionsverlust
   weg.

3. beleg_server.py (Port 4001) ist gelöscht.

Aus dem CRM-Launcher (`frontend/index.html`) wird auf die
externe URL verlinkt (öffnet in neuem Tab). Wenn das HR-Tool
Belege-Funktionen braucht, dann nur via dem ausgelagerten
tive-finance Repo, nicht durch Wiedereinführung in hr.html.

### Legacy-Status-Werte aufräumen
Im Code existieren Legacy-Status-Werte aus einer früheren Status-Sprache,
die mit dem neuen Personen-Modell nicht mehr vereinbar sind:

- `selected` — In `STATUS_FLOW` definiert (`hr.html:407`), aber nur in
  einem hardcoded Dummy-CV (`hr.html:784`) gesetzt. Mapping
  `'selected' → 'selection2'` existiert (`hr.html:15427`). Soll entfernt
  werden.
- `cv_received`, `in_system`, `presented`, `test_done` — Werden in
  Filter-Ausdrücken erwartet (`hr.html:5819, 14684, 14809`), sind aber
  nicht in `STATUS_FLOW` definiert. Reste einer früheren Migration.
- Parallele `selected`-Definition mit abweichender Farbe
  (`hr.html:5846`) — Dublette zur `STATUS_FLOW`-Definition.

Dies ist kein Drive-by-Refactoring, sondern Teil eines dedizierten
Vorhabens „Status-Migration zur neuen Status-Sprache".

### Personen-Datenmodell-Migration
Die aktuelle Struktur mit drei separaten Stores (`cvList` als
React-State, `employees` in `jsr_emp_v3`, `jsr_cv_archive_v1` für
konvertierte CVs) muss zu einer einzigen Personen-Tabelle konsolidiert
werden. Vor dem Produktivgang abgeschlossen. Greenfield, weil nur
Dummy-Daten existieren.

### Feldnamen-Migration
Im Code werden aktuell viele Feldnamen verwendet, die mit der Sektion
„Master-Feldnamen und Strukturen" nicht übereinstimmen. Die CLAUDE.md
beschreibt die Zielvorgabe, der Code ist noch nicht dort.

Betroffen sind unter anderem:

- **Bank**: heute teilweise `bank_account` (`hr.html`), teilweise
  `bank_iban` (`mitarbeiter.html`) als Einzelfelder. Ziel: strukturierter
  `bank: { name, iban, bic }`-Block.
- **Ausweis**: heute `id_card` und `id_number` parallel. Ziel: nur
  `id_number`.
- **Position**: heute `position` in `hr.html`/`mitarbeiter.html`, `role`
  in `client.html`. Ziel: nur `position`.
- **Vertragsdaten**: heute flach (`contract_start`, `contract_end`, …)
  und verschachtelt (`contract.start_date`, …) parallel. Ziel: nur
  verschachtelt `contract.{ signed_at, start, end, title, project }`.
- **Eintrittsdatum**: heute parallel als `hire_date`, `contract_start`,
  `contract.start_date`, `start_date`. Ziel: nur `contract.start`.
- **Stundenlohn**: heute `hourly_rate` als gespeicherte Größe am
  Mitarbeiter. Ziel: entweder entfernen oder nur als abgeleiteten
  Anzeigewert führen — die Quelle ist immer das Monatsgehalt (siehe
  Gehaltsmodell).

Diese Migration ist kein Drive-by-Refactoring, sondern Teil eines
dedizierten Aufräum-Vorhabens. Da bisher nur Dummy-Daten existieren,
ist Greenfield — keine Migration echter Datensätze nötig.

### Inkonsistente unpaid-Modellierung
Im Code existiert an mehreren Stellen die Konstruktion `type:'unpaid'`
+ `paid:true` (z. B. `hr.html:2054-2055`), bei der der `paid`-Flag den
Typ-Namen überschreibt. Das war ein Notbehelf für „sonstige
Abwesenheit, die doch bezahlt werden soll".

Mit dem neuen Abwesenheits-Modell entfällt dieser Fall: `unpaid` ist
immer unbezahlt, `vacation`/`sick` sind immer bezahlt. Code-Stellen mit
`unpaid` + `paid:true` müssen bereinigt werden — entweder zu
`vacation`/`sick` umetikettiert oder durch eindeutige `unpaid` +
`paid:false`-Logik ersetzt.

Kein Drive-by-Refactoring, sondern Teil eines dedizierten Aufräum-
Vorhabens. Greenfield, weil nur Dummy-Daten existieren.

### Gehalts-Verknüpfung zu Abwesenheiten
Die Anbindung des Abwesenheits-Modells an die Gehaltsberechnung ist im
Code aktuell nicht klar verifizierbar. Eine explizite Stelle, an der
`unpaid`-Tage anteilig vom Monatsgehalt abgezogen werden, ist nicht
eindeutig gefunden worden.

Vor dem Produktivgang muss verifiziert (und falls nötig ergänzt)
werden, dass:

- `unpaid`-Tage zu einer korrekten Lohnkürzung in der Lohnabrechnung
  führen.
- `vacation` und `sick` keine Auswirkung auf das Brutto haben.
- Die Soll-/Ist-Stunden-Berechnung (sobald implementiert, siehe
  Schichtmodell) Abwesenheiten korrekt einbezieht.

Risiko bei Nicht-Beachtung: Gehälter sind unstimmig, Mitarbeiter werden
zu viel oder zu wenig bezahlt.

## Auth-Konsolidierung — offene Go-Live-Blocker

Kontext: Login/Rollen/Portale laufen bereits über Supabase (`app_users` +
`roles_definitions`, RLS aktiv). Die User-Verwaltung wird in `hr.html`
(`AppUsersView`, Tab „App-User") schrittweise aufgebaut (Bausteine C1–C4).
Zwei Punkte müssen vor dem Produktivgang zwingend abgeschlossen sein:

### Letzter-aktiver-Admin-Guard — MUSS VOR GO-LIVE
Admin = User mit Rolle `management` oder `hr` (siehe `is_admin()` in
`supabase/schema_auth.sql`). Es gibt zwei Wege, sich (oder alle)
auszusperren:

1. Den letzten aktiven Admin **deaktivieren** (`app_users.active=false`).
2. Dem letzten aktiven Admin die **Rolle entziehen** (`role_keys` ohne
   `management`/`hr`) — ab Baustein C2b (Rollen-Editor) möglich.

Folge: Niemand kommt mehr ins HR-Portal, und die User-Verwaltung liegt
hinter `is_admin()` → Reparatur nur noch direkt im Supabase-SQL-Editor.

Stand: Der Self-Guard aus C2a verhindert nur die **Selbst-Deaktivierung**
der eigenen Zeile. C2b ergänzt clientseitig: eigene Zeile — `management`/
`hr` nicht abwählbar; fremde Zeile — Blockade, wenn dadurch der letzte
aktive Admin entfiele (Zählung aktiver Admin-User im State).

Der Client-Check ist die UX-Schranke, **nicht** die harte Absicherung.
Vor Go-Live zusätzlich nötig: ein **DB-Trigger oder eine Policy**, die auf
Datenbankebene garantiert, dass mindestens ein aktiver `management`/`hr`-
User bestehen bleibt (deactivate/role-removal sonst ablehnen). Erst damit
ist der Aussperr-Vektor wirklich dicht.

### Altvokabular-Bug `hr.html:13789-13790` (Baustein D)
`team?.role_id === 'role_superadmin'` / `'role_teamlead'` verwenden das
alte `PRESET_ROLES`-Vokabular (`role_`-Präfix). `gate()` setzt heute aber
`role_keys` (ohne Präfix), **kein** `role_id` → `isHR`/`isTeamLead` an
dieser Stelle sind effektiv immer `false`. Latente tote Logik. Beim
`PRESET_ROLES`-Removal (Baustein D, zusammen mit `SuperAdminView`)
mitaufräumen.

## Technologie-Stack

### Backend (`backend/`)
- **FastAPI 0.115** + Uvicorn — REST API unter `/api/v1`
- **SQLAlchemy 2 (async)** + **asyncpg** + **Alembic** — PostgreSQL 16
- **Pydantic v2** für Settings/Validation
- **Celery 5.4 + Redis 7** — Hintergrund-Tasks, Beat-Scheduler
  (täglich Job-Scan 07:00, wöchentlich Enrichment So 02:00)
- **Playwright (chromium)** für Headless-Crawling
- **httpx + BeautifulSoup + lxml** für klassisches Scraping
- **openpyxl** für Excel-Export
- **Anthropic SDK 0.40** für KI-Scoring (optional)

### Frontend (`frontend/`)
- **Keine Build-Pipeline**: Trotz `src/`-Ordner (weitgehend leer) sind die
  HTML-Dateien standalone und laden React 18, Babel-Standalone und xlsx
  zur Laufzeit über **unpkg-CDN**.
- `src/lib/api.js` existiert als Vite-Client (`import.meta.env.VITE_API_URL`),
  wird von den HTML-Modulen praktisch nicht genutzt.

### Infrastruktur
- `docker/docker-compose.yml` startet **nur** `postgres` + `redis`.
  Die im README erwähnten `api`/`worker`/`beat`-Services sind dort nicht
  definiert.

## Ordnerstruktur
```
tourism-leads/
├── backend/
│   ├── app/
│   │   ├── main.py              FastAPI Entry (6 Router)
│   │   ├── core/config.py       Pydantic Settings
│   │   ├── api/routes/          companies, contacts, jobs, activities, crawler, export
│   │   ├── models/models.py     ORM: Company, Contact, JobPosting, CrmActivity, CrawlerRun
│   │   ├── crawler/             company_crawler, job_signal_monitor, apollo_*, career_*, rfp_*, playwright_*
│   │   ├── tasks/celery_app.py  Celery + Beat-Schedules
│   │   └── db/session.py
│   ├── schema.sql + hr_schema.sql
│   └── requirements.txt
├── frontend/                    Standalone HTML-Module (React via CDN)
│   ├── hr.html / mitarbeiter.html / client.html   ← Kern
│   └── src/                     (weitgehend leerer Vite-Stub)
├── docker/docker-compose.yml    postgres + redis
└── README.md                    beschreibt nur den ursprünglichen Tourism-Leads-Teil
```
