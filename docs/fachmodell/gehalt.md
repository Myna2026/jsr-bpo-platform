# Gehaltsmodell

> Verbindliche fachliche Vorgabe (ausgelagert aus `CLAUDE.md`, Stand 2026-09-15).
> Bei Konflikten mit bestehendem Code gilt dieses Dokument. Kurzfassung und
> Leitplanken stehen in `CLAUDE.md`.

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

