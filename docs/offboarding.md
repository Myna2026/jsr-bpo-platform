# Offboarding / Kündigung

> Verbindliche fachliche Vorgabe (ausgelagert aus `CLAUDE.md`, Stand 2026-09-15).
> Bei Konflikten mit bestehendem Code gilt dieses Dokument. Kurzfassung und
> Leitplanken stehen in `CLAUDE.md`.

**Stand 2026-09-15:** Das fachliche Modell unten ist die Zielvorgabe. Umgesetzt
sind Schnitt 1 (Kündigen-Modal mit Kündigungsdatum `notice_date`, Modalität,
Notiz), Schnitt 2 (datumsgetriebene Planbarkeit via `empExitedBy`), Schnitt 3
(Urlaub datumsbasiert, war schon da) und Schnitt 4a (generiertes
Kündigungsschreiben, HR-only). Die Stati `freigestellt_bezahlt` /
`freigestellt_unbezahlt` existieren (STATUS_FLOW, PAID_PHASES). **Offen ist nur
4b:** Upload des unterschriebenen Originals als Storage-Bucket mit RLS (nicht
Base64 im Datensatz).

## Fachliches Modell
- **Zwei getrennte Daten:** *Kündigungsdatum* (die Kündigungsfrist rechnet ab
  hier) und *Austrittsdatum* (= `termination_date`, der letzte Tag des
  Arbeitsverhältnisses). `termination_date` existiert bereits im Datenmodell;
  ein eigenes **Kündigungsdatum-Feld fehlt noch**.
- **Zwischenzeit** (Kündigung → Austritt) ist eine **frei kombinierbare
  Mischung**: arbeiten / Resturlaub / bezahlt freigestellt / unbezahlt
  freigestellt. Kein starres Entweder-oder.
- **Neuer Status `freigestellt`:** noch angestellt, **Lohn läuft weiter** (muss
  in `PAID_PHASES` des Lohnlaufs), aber **nicht einsatzplanbar**. Die ~20
  `status==='active'`-Filter (Workforce/Projekte/Verfügbarkeit) schließen ihn
  automatisch aus, weil er nicht `active` ist. Existiert noch nicht.

## Die 4 Schnitte
1. **Urlaub datumsbasiert:** beantragter Zeitraum — *von* UND *bis* — muss
   `<= termination_date` liegen, sonst **hart blocken**. An drei Stellen
   konsistent: MA-Antrag (`submitVacationRequest`), HR-Genehmigung
   (`updateRequest`) UND im `respond_counter`-RPC. **Kein Austrittsdatum
   gesetzt = keine Grenze.** Kein neues Datenmodell nötig, steht allein.
2. **Datenmodell:** Feld *Kündigungsdatum* + Status `freigestellt`
   (`STATUS_FLOW` + `PAID_PHASES` + Anzeige/Badge). **SQL zuerst.**
3. **Offboarding-Flow** im Kündigen-Modal (`confirmTerminate`): Kündigungsdatum
   + Austrittsdatum + Modalität der Zwischenzeit erfassen, Status/Daten setzen.
4. **Kündigungsdokument — zwei gleichwertige Wege:** (a) System erzeugt ein PDF
   zum Download/Ausdruck, (b) HR trägt die Daten manuell ein und lädt ein
   vorhandenes Dokument hoch. Die **Datenerfassung ist unabhängig** vom
   Dokument-Weg. Der Upload braucht **Datei-Storage** (neuer Bereich).

**Abhängigkeiten:** 2 vor 3 vor 4; Schnitt 1 steht allein.
**Reihenfolge:** 1 → 2 → 3 → 4.

