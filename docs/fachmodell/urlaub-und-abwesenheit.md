# Urlaubs- und Abwesenheits-Modell

> Verbindliche fachliche Vorgabe (ausgelagert aus `CLAUDE.md`, Stand 2026-09-15).
> Bei Konflikten mit bestehendem Code gilt dieses Dokument. Kurzfassung und
> Leitplanken stehen in `CLAUDE.md`.

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

