# Offene technische Schulden und Go-Live-Blocker

> Ausgelagert aus `CLAUDE.md` (Stand 2026-09-15). Jeder Punkt ist ein eigenes
> Vorhaben, kein Drive-by-Refactoring. Erledigte Punkte bleiben als Historie
> unten stehen.

## Offene Schulden

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

### Lohnlauf-Zugehörigkeit über Beschäftigungszeiträume (offen: `inactive`)
Der Lohnlauf (`PayrollView`) bestimmt die Monats-Zugehörigkeit eines
Mitarbeiters seit dem Datums-Fix **datumsgetrieben** (Eintritt =
`contract.start`, Austritt = `termination_date`), nicht mehr über den
Live-`status`. Damit bleiben historische Monate stabil und ein im
Austrittsmonat Gekündigter wird noch abgerechnet.

**Ungelöst:** `inactive` (Elternzeit, Langzeitkrankheit) hat keinen
eigenen Zeitraum. Ein *aktuell* inaktiver Mitarbeiter fällt darum aus
**allen** Monaten des Lohnlaufs — auch aus denen, in denen er aktiv war.
Das ist dieselbe Krankheit wie der behobene Hauptbug (Status statt
Historie), nur für einen anderen Status. Saubere Lösung braucht echte
**Beschäftigungszeiträume** (z. B. `inactive_since`/`inactive_until` oder
allgemein eine Statushistorie mit Von-Bis), nicht einen einzelnen
Live-Statuswert. Eigener Vorhaben-Schnitt, vor Produktivgang zu klären.

### Urlaubs-Genehmigung prüft den Mitarbeiter-Status nicht (offen)
`VacationRequestsView.updateRequest` genehmigt ohne Status-Check — auch für
`terminated`/`inactive` Mitarbeiter lässt sich Urlaub genehmigen und eine
Absence schreiben. Vor Produktivgang: Genehmigung auf beschäftigte Status
beschränken (bzw. Antrag für gekündigte/inaktive MA gar nicht erst zulassen
oder sichtbar warnen).


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

**Status:** DB-Ebene umgesetzt in `supabase/schema_auth.sql` §10 —
CHECK `app_users_kunde_exclusive` (Kunden-Rollen-Exklusivität) +
Trigger `app_users_last_admin` (`enforce_last_admin()`, statement-level).
Verbleibendes Restrisiko: Der Trigger zählt im Snapshot der eigenen
Transaktion → unter `READ COMMITTED` können **zwei gleichzeitige**
Deaktivierungen verschiedener Admins beide „≥1" sehen und committen
(Write-Skew → theoretisch 0 aktive Admins). Bei 3–4 Admins akzeptabel.
Spätere Härtung: Advisory-Lock im Trigger oder `SERIALIZABLE`-Isolation.

### Altvokabular-Bug `hr.html:13789-13790` (Baustein D)
`team?.role_id === 'role_superadmin'` / `'role_teamlead'` verwenden das
alte `PRESET_ROLES`-Vokabular (`role_`-Präfix). `gate()` setzt heute aber
`role_keys` (ohne Präfix), **kein** `role_id` → `isHR`/`isTeamLead` an
dieser Stelle sind effektiv immer `false`. Latente tote Logik. Beim
`PRESET_ROLES`-Removal (Baustein D, zusammen mit `SuperAdminView`)
mitaufräumen.


## Erledigt (Historie)

### Belege-Auskapselung

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

