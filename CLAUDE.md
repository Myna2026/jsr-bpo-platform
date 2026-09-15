# CLAUDE.md — TIVE 360° / JSR BPO Intelligence Platform

## Was die Anwendung macht
Ursprünglich DACH Tourismus-Lead-Management (siehe `README.md`, überholt),
inzwischen eine **BPO Intelligence Platform** für ein Call-Center: HR-Portal,
Mitarbeiter-Portal, Kunden-Portal plus Nebenseiten, als monolithische
HTML-Dateien in `frontend/` (React 18 via CDN, kein Build-Schritt, Babel wird
erst beim Deploy vorkompiliert). Daten, Auth und RLS laufen über **Supabase**
(Projekt `tive360-plattform`, ref `msdiyjxckmpvuomnhvjp`), Automatik über Edge
Functions in `supabase/functions/`. Buchhaltung/Belege sind ausgelagert
(Repo `tive-finance`, https://tive-finance.vercel.app/).

Wie das System gebaut ist (Portale, Rollen, Tabellen, Importe, Konventionen):
**`ARCHITEKTUR.md`**. Fachliche Detail-Vorgaben: **`docs/`** (Verzeichnis am
Ende dieser Datei).

## Modul-Scope
- **Kernmodule** (hier wird weiterentwickelt): `frontend/hr.html`,
  `frontend/mitarbeiter.html`, `frontend/client.html`.
- **Nachrangig**: `leads.html`, `stempel.html`, Nebenseiten (`bewerber.html`,
  `index.html`, `payslip_preview.html`, `setup.html`, `showcase.html`,
  `dummy_loader.html`). Bei umfangreichen Änderungen dort vorher klären, ob
  sich der Aufwand lohnt.
- Vom User am 2026-05-26 als langfristiger Scope festgelegt. Bei Konflikten
  mit `README.md` gilt CLAUDE.md.

**Verhaltensregeln:**
- Bei vagen Anfragen kurz nachfragen, statt stillschweigend ein Modul
  anzunehmen. Nur bei eindeutigem inhaltlichem Hinweis („Bewerber",
  „Schicht", „Kunde") ohne Rückfrage loslegen.
- Architektur- und übergreifende Vorschläge an den drei Kernmodulen
  ausrichten.
- Nutzer sind nicht-technisch: System entscheidet vor, bietet nur valide
  Optionen an, wenige Klicks. Constraints werden verhindert, nicht gemeldet.

## Fachliche Leitplanken (Kurzfassung, Details in `docs/`)
Diese Regeln sind verbindlich; bei Konflikten mit bestehendem Code gilt die
Vorgabe. Vollständige Modelle: `docs/fachmodell/`.

**Personen und Mitarbeiter** (`docs/fachmodell/personen-und-datenmodell.md`)
- Eine Person = ein Datensatz mit stabiler ID über den ganzen Lebenszyklus
  (CV → Mitarbeiter → Austritt). Kein Umkopieren beim Statuswechsel.
- `position` ist Master; die Kategorie (`agent` / `overhead` / `admin`) wird
  daraus abgeleitet, nie doppelt gespeichert. Neue Positionen müssen in die
  Tabelle im Doc, sonst lehnt das System sie ab.
- Projektzuweisungen `project_assignments[{employee_id, project_id, skill,
  start_date, end_date}]` sind die operative Kernstruktur. Wechsel = alte
  Zeile schließen, neue anlegen; nie überschreiben oder löschen. Agent: genau
  eine offene Zuweisung. Overhead: mindestens eine. Admin: keine.
- `cv_skills` (Selbstauskunft) und Projekt-Skill (aus der Zuweisung) sind nie
  austauschbar, kein Fallback. Operative Auswertungen nutzen nur den
  Projekt-Skill.
- Master-Feldnamen: `bank:{name,iban,bic}`, `id_number`, `position`,
  `contract:{signed_at,start,end,title,project}`. `contract.start` ist die
  einzige Wahrheit für Eintritt/Bezahlungsbeginn. Alte flache Namen
  (`bank_iban`, `id_card`, `role`, `contract_start`, `hire_date`, …) werden
  nicht neu verwendet.
- 19 Status-Werte (CV-Funnel `cv_inbound` … `selection2`, Mitarbeiter
  `contract` → `training_planned` → `training` → `active` / `inactive`,
  `parking`, terminal `rejected_*` / `blacklist` / `terminated_*`), dazu
  inzwischen `pool` und `freigestellt_bezahlt` / `freigestellt_unbezahlt`.
  Alle Übergänge manuell durch HR. Harte Vorbedingung: `training_planned` /
  `training` nur ab `contract`. Neuer CV-Status braucht auch den
  DB-Constraint `cvs_status_valid`.

**Urlaub und Abwesenheit** (`docs/fachmodell/urlaub-und-abwesenheit.md`)
- Drei Typen in `employee.absences[]` mit `type`: `vacation` (bezahlt,
  Antrag), `unpaid` (unbezahlt, Antrag oder HR-Eintrag), `sick` (bezahlt,
  HR-Eintrag). `unpaid` + `paid:true` gibt es nicht mehr.
- Anspruch kalenderjahr-basiert (Eintrittsjahr 18 anteilig, Folgejahre 20,
  Admin-konfigurierbar, manueller Override je MA). Planungs-Sperre:
  `planbar = Anspruch - reserviert - verbraucht`. Halbe Tage nur glatt halb.
- Antrag im MA-Portal, Entscheidung im HR-Portal als Ampel (Grün / Gelb mit
  MA-Bestätigung / Rot). Freigegebene Absences sind Single Source of Truth
  für Workforce, Lohn und Auswertungen.
- Abwesend = nicht planbar, typ-agnostisch (`isAbsent`).

**Gehalt** (`docs/fachmodell/gehalt.md`)
- Festes Monatsgehalt in nativer Währung; Stundenlohn ist abgeleitet, kein
  gepflegtes Feld. Auszahlung am 15. des Folgemonats, Boni (pauschal, KPI,
  Referral in zwei Tranchen ab `active`, Drehrad) als eigene Zeilen im
  selben Lohnlauf. Lohnlauf-Zugehörigkeit datumsgetrieben
  (`contract.start` / `termination_date`), nicht über den Live-Status.

**Schichtplanung** (`docs/schichtplanung.md`)
- `SimpleShiftView` ist das Alltags-Werkzeug, `WorkforcePlanningView` ist
  „Beta" (nur HC Sales). Beide teilen `shift_assignments`. Verfügbarkeits-
  und Schicht-Regeln nur in den Top-Level-Funktionen `shiftEmpDayOk`,
  `shiftEmpAllowsShift`, `shiftValidTemplates`, `shiftConfigFor`,
  `shiftAbsent` ändern, dann gilt es für beide.

**Kennzahlen**
- Rankings und Aggregationen immer je Projekt+Skill, nie über Skill-Grenzen.
- Nie Fake- oder Dummy-Daten bei leerem Ergebnis; Loads an den Login
  koppeln; Herkunft jeder Zahl sichtbar (siehe `ARCHITEKTUR.md` §8).

## Deployment und Git

**Frontend** geht per `./deploy.sh` (als `bash -c 'bash deploy.sh'`) per rsync
auf die Hetzner-VM `root@178.104.147.208` nach `/var/www/tive360/<portal>/`,
serviert von Caddy (hr./mitarbeiter./client./tive360.de). **Nicht Vercel**,
`frontend/vercel.json` ist ein Altpfad. Das Script läuft zuerst alle Checks in
`scripts/checks/` (jsx/syntax/ma/field/eslint/tdz/shared/status/menu +
Smoketest), sichert den Live-Stand (letzte 10, `./rollback.sh`), kompiliert
`text/babel` vor (classic runtime, `retainLines`) und stempelt eine Build-ID.
Ein fehlgeschlagener Check überträgt nichts.

**Supabase** rollt Claude selbst aus, im selben Zug wie der Edit:
- Edge Function: `supabase functions deploy <name> --use-api`
- Migration: `supabase db query --linked -f migrations/<datei>.sql`
  (`psql` ist nicht installiert). Additive Migrationen (neue Tabelle, Spalte,
  Policy, Index) ohne Rückfrage; alles, was Bestehendes ändert oder löscht,
  erst fragen. Kurz melden, was eingespielt wurde.

**Git:**
- `deploy.sh` committet nicht. Nie „deployt und committet" melden, wenn nur
  deployt wurde.
- Commits nur auf ausdrückliche Aufforderung. Vor dem Stagen gezielt Dateien
  benennen (kein `git add -A` / `.`) und gegen `.gitignore` prüfen.
- Vor jedem `git push`: `git status` und `git diff` zeigen und auf „ok"/„push"
  warten. Der User pusht meist selbst über GitHub Desktop; bei
  Credentials-Fehlern im Terminal darauf hinweisen.
- Commit-Messages knapp, ohne Co-Author- oder Modell-Trailer.

**Secrets:** nie `.env`-Dateien oder Keys committen (`backend/.env` ist in
`.gitignore`; betrifft `APOLLO_API_KEY`, `HUNTER_API_KEY`, `PROXYCURL_API_KEY`,
`ANTHROPIC_API_KEY`, `SECRET_KEY`, DB-Passwörter, Vercel-Tokens). Falls eine
`.env.example` nötig ist: nur Platzhalter.

## Prozess-Regeln
- **Referenz-Check vor Komponenten-Removal:** vor dem Löschen prüfen, was die
  Komponente rendert/mountet, nicht nur, ob ihr Name referenziert wird
  (`grep -n "<Name" innerhalb des Löschbereichs` + welche
  localStorage-Keys/Business-Logik der Block schreibt). Beinahe-Unfall
  2026-07-11: `SuperAdminView` sah tot aus, mountete aber die gesamte
  Business-Config (`SystemSettingsTab`, `ProjectsAdminTab`,
  `ClientAccountsTab`).
- **Nach Änderungen an Neuanlage-Modals** immer beide Fälle testen (Entity
  vorhanden und `null`); `no-undef` fängt das nicht.
- **Zeitzonen:** lokale Daten mit `isoLocal()`, nie `toISOString()` auf ein
  lokales `Date`.
- **Sichtbare Texte** ohne lange Gedankenstriche (Komma, Doppelpunkt, Punkt).
- **Dialoge** in-app (`uiConfirm` / `uiPrompt`), nicht `window.confirm`.
- **Shell:** keine verschachtelten `$()` oder gebündelten Befehle, nicht ins
  Projektverzeichnis `cd`en (`git -C` bzw. schon im Root).
- Offene Feature-/Design-Specs nicht als Multiple-Choice abfragen; kurz offen
  fragen oder mit einer Empfehlung vorangehen.

## Offene Go-Live-Blocker (Kurzliste)
Details, Historie und Erledigtes: `docs/technische-schulden.md`.
- Personen-Datenmodell-Migration (drei Stores → eine Personen-Tabelle) und
  Feldnamen-Migration auf die Master-Namen.
- Legacy-Status-Werte (`selected`, `cv_received`, `in_system`, …) entfernen.
- `unpaid` + `paid:true` bereinigen; Gehalts-Verknüpfung zu Abwesenheiten
  verifizieren.
- Lohnlauf: `inactive` hat keinen Zeitraum, braucht Beschäftigungszeiträume.
- Urlaubs-Genehmigung prüft den MA-Status nicht.
- Letzter-aktiver-Admin-Guard: DB-Trigger steht, Write-Skew-Restrisiko;
  Altvokabular `role_id === 'role_*'` in `hr.html` (Baustein D).
- Offboarding 4b: Upload des unterschriebenen Kündigungsschreibens
  (Storage-Bucket + RLS), siehe `docs/offboarding.md`.

## Dokumente
| Datei | Inhalt |
|---|---|
| `ARCHITEKTUR.md` | Wie das System gebaut ist: Portale, Rollen, Tabellen, Importe, Wochenbericht, KI, Konventionen |
| `docs/fachmodell/personen-und-datenmodell.md` | Positionen/Kategorien, Projektzuweisungen, Master-Feldnamen, Personen-Lebenszyklus, 19 Stati |
| `docs/fachmodell/urlaub-und-abwesenheit.md` | Urlaubsanspruch, Antragsverfahren, Verbrauch, Jahresübergang, Kündigung; Abwesenheits-Typen |
| `docs/fachmodell/gehalt.md` | Monatsgehalt, Bonus-Typen, Auszahlungsrhythmus, Lohnabrechnung |
| `docs/schichtplanung.md` | SimpleShiftView vs. WorkforcePlanningView, geteilte Prüf-Logik |
| `docs/offboarding.md` | Kündigungsmodell, 4 Schnitte, Stand |
| `docs/technische-schulden.md` | Offene Schulden, Auth-Go-Live-Blocker, Erledigtes (Belege-Auskapselung) |
| `docs/technologie-stack.md` | Backend-Stack (FastAPI/Celery, Tourism-Leads-Teil), Docker, Ordnerstruktur |
| `README.md` | Ursprünglicher Tourism-Leads-Teil, überholt |

## Ordnerstruktur (Kurz)
```
frontend/            hr.html / mitarbeiter.html / client.html (Kern), Nebenseiten,
                     shared/ (jsr-calc.js, presentation-slides.js), assets/
supabase/functions/  Edge Functions (Agenten, Importe, Mailer, nlquery, assistant, …)
supabase/*.sql       schema_auth.sql (Rollen, RLS-Helfer, Guards) + Alt-Schemata
migrations/          alle DB-Änderungen als datierte SQL-Dateien
scripts/checks/      Deploy-Vorab-Checks, scripts/precompile/ Babel-Precompile
deploy.sh            Frontend-Deploy (rsync), rollback.sh
backend/, docker/    ursprünglicher Tourism-Leads-Teil (FastAPI, Celery, Postgres)
demo/                Vorführ-Mandant „Reisewelt"
```
