# ARCHITEKTUR.md — Wie das System gebaut ist

Dieses Dokument beschreibt die **Struktur** der TIVE-360°-/JSR-BPO-Plattform:
Portale, Rollen, Datenmodell, Tabellen, Importe, Wochenbericht und die
Konventionen. Es beantwortet „**wie ist das gebaut**" — für Entwickler, für den
KI-Assistenten und für alle, die später dazukommen.

**Abgrenzung:**
- **Bedienung** („wie lege ich einen Mitarbeiter an") steht im **Handbuch**
  (`SYSTEM_MANUAL` in `frontend/hr.html`, angezeigt unter „Wissen System").
- **Änderungs-Regeln und fachliche Vorgaben** (Feldnamen-Migration, Status-Modell,
  Urlaubs-/Gehaltsmodell im Detail) stehen in **`CLAUDE.md`**. Bei Konflikten gilt
  CLAUDE.md. Dieses Dokument dupliziert das nicht, sondern verweist darauf.
- Der ursprüngliche Tourism-Leads-Teil steht in `README.md` und ist überholt.

---

## 1. Portale & Frontends

Es gibt **drei Portale**, unterschieden über die Rolle (Feld `portals` in
`roles_definitions`):

| Portal | Datei | Für wen | Domain |
|---|---|---|---|
| **HR** | `frontend/hr.html` | Overhead + Admin (Management, HR, Finance, Teamleiter, Projektleiter, QM, Trainer, ASP) | hr.tive360.de |
| **Mitarbeiter** | `frontend/mitarbeiter.html` | Agenten/Mitarbeiter (eigenes Login) | mitarbeiter.tive360.de |
| **Client** | `frontend/client.html` | Kunden (Rolle `kunde`) | client.tive360.de |

Dazu **login-freie öffentliche Seiten** (Token-basiert): `praesentation.html`
(Kundenbericht) und `showcase.html` (Bewerber-Showcase).

**Technik:** Standalone-HTML, **keine Build-Pipeline**. React 18, Babel-Standalone
und xlsx werden zur Laufzeit über CDN geladen; `deploy.sh` präkompiliert die
Babel-Blöcke, stempelt eine Build-ID und **rsynct auf einen Hetzner-Server hinter
Caddy** (NICHT Vercel). Der `src/`-Ordner (Vite-Stub) ist praktisch ungenutzt.
Backend (FastAPI/Celery/Playwright) existiert separat für Crawling; das CRM selbst
läuft direkt gegen **Supabase** (Postgres + Auth + RLS + Storage + Edge Functions).

---

## 2. Rollen & Rechte

**Login/Rollen laufen über Supabase.** Zwei Tabellen:
- `app_users` — verknüpft den Auth-User mit `role_keys text[]` (ein User kann
  mehrere Rollen haben) und optional `employee_id` / `client_id`.
- `roles_definitions` — je Rolle `label` + `portals text[]` (welche Portale sie
  öffnen darf).

**Rollen und ihre Portale** (Seed in `supabase/schema_auth.sql`):

| Rolle | Portale |
|---|---|
| `kunde` | client |
| `mitarbeiter` | mitarbeiter |
| `teamlead`, `qm`, `trainer`, `asp`, `projektleiter`, `hr`, `finance`, `management` | mitarbeiter + hr |

**RLS-Helfer** (SECURITY DEFINER, in `schema_auth.sql` u. a.):
`is_management()`, `is_hr()`, `is_finance()`, `is_admin()` (= management ODER hr),
`is_planner()`, `is_lead_only()`, `is_emp_in_my_project(uuid)`,
`get_my_employee_project_id()`. Alle Row-Level-Security-Policies bauen darauf auf.

**Wichtige Sicherheits-Muster:**
- **Sensible Spalten** (Gehalt, Bank) werden nicht per Client-Filter, sondern über
  **security-definer-Views + Policies** geschützt (Kunde/Teamlead/MA sehen sie
  nicht). HR sieht keine Management-Gehälter (Maskierungs-View + Trigger).
- **Projektbezug:** Projektleiter sehen/führen nur ihr Projekt — RLS über
  `is_lead_only()` + `project_id = get_my_employee_project_id()`.
- **Letzter-Admin-Schutz:** DB-Trigger `enforce_last_admin()` verhindert, dass der
  letzte aktive management/hr-User deaktiviert oder entrollt wird (Aussperr-Schutz).
- **Read-only-KI-Rolle:** `nlquery_ro` (nur SELECT auf eine Allowlist) für die
  Datenabfrage — siehe §8.

---

## 3. Datenmodell — die zentralen Größen

Verbindliche Details stehen in `CLAUDE.md` (Sektion „Datenmodell"). Kurzfassung:

- **Mitarbeiter = Person = eine ID, ein Lebenszyklus.** Eine Person ist EIN
  Datensatz mit stabiler ID; sie wechselt nur ihren `status` (19 Stati vom
  CV-Eingang bis Kündigung). Kein Umkopieren beim Statuswechsel.
- **Position → Kategorie** (abgeleitet, nicht doppelt gespeichert):
  Agent/Senior Agent/ASP/Supervisor = `agent`; Teamleiter/Trainer/QM/Projektleiter
  = `overhead`; HR/Management/Finance/IT = `admin`.
- **Projekt hat Skills** (z. B. „Holidaycheck" mit „Sales" + „Support"). Skill ist
  eine Eigenschaft des **Projekts**, kleingeschrieben.
- **Projektzuweisung** (`project_assignments`: employee ↔ project ↔ skill mit
  start/end) ist die operative Kernstruktur — KPIs, Schichten, Auswertungen laufen
  darüber. `end_date=null` = laufend. Historie bleibt erhalten.
- **CV-Skill ≠ Projekt-Skill:** `cv_skills` (Selbstauskunft) ist NICHT der
  Projekt-Skill (operative Wahrheit aus der Zuweisung). Kein Fallback dazwischen.

**Beziehungen (grob):**
```
projects (id, name, client, skills[])
   ▲ project_id
employees (id, status, position, project_id, project_skill, contract{}, absences[], bank{}, salary_currency)
   ▲ employee_id                        ▲ emp_id
project_assignments                     kpi_entries (je Agent, kpi_id, kw/year)
report_fte (fte je MA)                  kpi_project_entries (je Team)
absences (Tabelle) / shift_assignments  kpi_config (id, name, skill, level agent|team)
cvs (Bewerber) ── source ──> meta|Google Sheet|HR|cv|LP
windsor_leads (Meta-Rohdaten) ── Import ──> cvs
```

---

## 4. Tabellen-Landkarte (wofür + Eigenheiten)

**Mitarbeiter & Struktur**
- `employees` — alle Personen. **Eigenheiten:** `absences` ist ein **jsonb-Array**
  `[{type:'vacation'|'sick'|'unpaid', from, to, days}]` AM Mitarbeiter (nicht nur
  die Tabelle `absences`). `contract` ist **jsonb** `{start,end,signed_at,title,
  project}` — `contract.start` ist die EINZIGE Wahrheit für Eintritt/Bezahlbeginn.
  `bank` ist jsonb `{name,iban,bic}`. Gehälter nativ in `salary_currency`
  (Umrechnung EUR über `jsr_fx_rates_v1`).
- `projects` — id (text), name, client, `skills` (jsonb).
- `project_assignments` — employee ↔ project ↔ skill, mit start/end.
- `report_fte` — FTE-Standard je Mitarbeiter/Projekt.
- `org_nodes` — Organigramm (relational; `project_id = NULL` = Unternehmensleitung).

**Abwesenheit / Zeit / Schicht**
- `absences` (Tabelle) — daneben liegen Abwesenheiten AUCH als jsonb am employee
  (historisch). Urlaubsanträge vor Genehmigung in `jsr_vacation_requests_v1`.
- `shift_assignments` — Schichtplan (Zeile pro Zelle; geteilt von einfachem Planer
  und Workforce-Beta). `shift_checkins` — Ist-Anwesenheit.

**Kennzahlen (KPI)**
- `kpi_config` — Definition je Kennzahl: `id` (z. B. `kpi_178…`), name, skill,
  project_id, **level** `agent` | `team`. **Regel:** Kennzahlen immer über die
  `kpi_id` ansprechen, nie über den Namen raten.
- `kpi_entries` — Wert **je Agent** je Woche (emp_id, kpi_id, value, kw, year).
- `kpi_project_entries` — Wert **je Team** (project_id, skill, kpi_id, kw ODER
  month, year).
- `weekly_hours` (Stunden/Sales-Calls je MA/Woche, inkl. Mailer-Stunden),
  `weekly_calls` (answered/AHT/ACW), `weekly_gauges` (CSAT).
- `report_forecast` (Auftraggeber-Forecast fc_hours/planned_hours je KW),
  `report_longterm` (12-Monats-Kapazität, `rows` jsonb), `report_measures`
  (Maßnahmen), `report_fte`.
- `mail_daily` (geplant/gebaut je nach Stand) — Mail-Anzahl je MA/Tag.

**Bewerber**
- `cvs` — Bewerber-Trichter. **`source`** trägt die Herkunft:
  `meta` (Anzeigen), `Google Sheet` (Sync), `HR`, `cv` (Funnel-Übernahme), `LP`.
  Telefon ist E.164, mit **Unique-Index** (`idx_cvs_phone_unique`, partiell) →
  eine Nummer, ein Bewerber.
- `windsor_leads` — Staging der Meta-Bewerbungen (Windsor `facebook_leads`);
  Windsor-Originalspalten (`vor-_und_nachname`, `__telefonnummer__` …),
  `lead_id` = Idempotenz-Schlüssel.
- `call_criteria` / `call_samples` / `call_scores` — Call-Qualitäts-Stichproben.

**Marketing / Importe / Konfiguration**
- `windsor_marketing` — Recruiting-Werbung (date, datasource facebook/instagram,
  spend, reach …).
- `data_imports` — Protokoll jedes Datei-Imports (project_id, source_type, kw,
  year, status, uploaded_by, created_at). **Herkunft immer sichtbar.**
- `import_aliases` — Kürzel/Name → employee_id („einmal lernen", dann greift es).
- `upload_schedule` + `upload_project_owner` — Rhythmus/Fälligkeit/Kulanz/
  Zuständiger je Quelle (Upload-Ampel; live berechnet, kein Status-Speicher).
- **`app_config`** — generischer Key/Value-Store (`key`, `value` jsonb) für alle
  Frontend-Konfigurationen (`jsr_*`), z. B. `jsr_kb_v1` (Wissensbasis),
  `jsr_system_manual_v1` (gespiegeltes Handbuch für den Assistenten),
  `jsr_cv_sync_config_v1`, `jsr_referral_config_v1`, Cockpit-Layouts, …
- `presentations` / `report_measures` / `report_forecast` — Kundenberichte (§7).

---

## 5. Importe — welche Datei befüllt was

Ein Datensatz kommt **nie still** ins System: Erkennung am **Inhalt**, Datum aus
der Datei, täglicher Upload **ergänzt statt zu ersetzen**, Werte korrigierbar,
Rohdatei in den Storage (`weekly-imports`), Eintrag in `data_imports`. Unbekannte
Namen werden gemeldet, nie stumm verworfen (`import_aliases` lernt sie).

Zentral im HR-Portal unter **Datenimport** (`UPLOAD_SOURCES`, eine Wahrheit für
Datenimport + Upload-Plan):

| Datei (Muster) | Quelle | Befüllt |
|---|---|---|
| `performance_kpis_25HXK_<ts>.xlsx` | Rohdaten-Excel | `weekly_hours` (Stunden je Skill, Mailer-Stunden = Spalte AQ) |
| `<Datum>_Agent_Performance_Summary.csv` | Call-CSV | `weekly_calls` (answered/AHT/ACW) |
| `Gauges_<Datum>.xlsx` | Gauges | `weekly_gauges` (CSAT) |
| `Table_Booking_KPIs.xlsx` | Booking-Agent | `kpi_entries` (Conversion, Buchungen, Sales Calls je Agent) |
| `Table_Weeks/Months_Booking_KPIs.csv` | Booking-Team | `kpi_project_entries` (KW/Monat) |
| `FC_<Monat>_25Hrs__SALES/Support.xlsx` | Forecast | `report_forecast` (fc_hours) |
| `Long_Term_Capacity_25H_Sales_Support.xlsx` | Langzeit | `report_longterm` (Kreuztabelle: Zeilen=Kennzahlen, Spalten=Monate) |
| `HolidaycheckAG_CS_25hrs_<ts>.xlsx` | Mail-Excel | (in Arbeit) Mail-Anzahl → Mails/h |

**Automatik:** Der Bewerber-Import (Meta `windsor_leads` + Google-Sheet-Sync) läuft
serverseitig über die Edge Function **`applicant-import`** (täglich per Cron ~02:00
UTC, nach dem Windsor-Lauf 01:00). Telefon-Dubletten werden **nicht** automatisch
entschieden, sondern zurückgehalten (Dubletten-Bereich). Ein manueller Knopf bleibt.

**Herkunfts-Attribution:** Bewerbungen werden nach `cvs.source` getrennt
(Meta-Anzeigen vs. Google-Sheet vs. übrige) — überall wo Bewerbungszahlen
erscheinen; Kosten je Bewerbung rechnen nur mit `source='meta'`.

---

## 6. Der Wochenbericht (Kundenbericht)

Der Bericht ist **EIN Deck** mit fester Folienreihenfolge, gerendert vom geteilten
plain-JS-Renderer **`frontend/shared/presentation-slides.js`** (`window.PRES`,
`deckSlides(ctx)` + `deckSlideKeys(ctx)`; React.createElement `h()`, `cqw`-Einheiten
für ein festes 16:9-Format).

- **Datenfluss:** In `hr.html` wird aus den DB-Tabellen (`kpi_entries`,
  `weekly_*`, `report_forecast/longterm/measures`, `report_fte`, Call-Qualität …)
  per `applyImport*`-Funktionen ein `deck.teams[skill]`-Objekt aufgebaut
  (fteList/bands, stunden, cr, csat, callaht, mail, langzeit, massnahmen).
- **Struktur:** ein Bericht, Sales-Set (mit CR) + „Support"-Trenner + Support-Set
  (mit Mail/AHT je Agent). Bei zu vielen Personen **paginieren** die Agenten-Folien
  automatisch (nichts wird abgeschnitten).
- **Ausgabe:** Vorschau im HR-Tool, öffentliche Seite `praesentation.html`
  (Token-Login-frei), PDF über Browser-Druck. Kunden-Look (Farbe/Logo/Font) je
  Projekt über Templates. Management kann Maßnahmen live pflegen (`report_measures`).
- **Wichtig fürs PDF:** feste 16:9-Höhe → lange Listen/Bäume paginieren, nicht
  scrollen. Der KI-Datenbaum/Organigramm-Baum wächst nur im Browser.

---

## 7. KI-Bausteine

Zwei Edge Functions, beide über die Anthropic-API (Secret `ANTHROPIC_API_KEY`):

- **`nlquery`** (Datenabfrage per Sprache, Management-only): Frage → Klärung
  (mehrschrittig) / „geht nicht" (mit Alternativen) / SELECT-Abfrage. Läuft
  ausschließlich lesend über die DB-Funktion `nlquery_exec` mit der Rolle
  **`nlquery_ro`** (nur SELECT auf eine Allowlist, kein Schreiben). Schema hybrid:
  kuratierter Kern + Live-Glossar (kpi_config/projects). Antwort in Klartext, mit
  Datenbaum (welche Bereiche gelesen werden).
- **`assistant`** (Wissens-Assistent, alle HR-Portal-Nutzer): beantwortet
  „wie/wo"-Fragen aus Handbuch (`jsr_system_manual_v1`) + Wissensbasis
  (`jsr_kb_v1`) + Live-Fakten (Uploads/Rollen/KPIs/Projekte) + Navigations-
  Landkarte. Kurz, in Schritten, mit Sprung-Ziel; sagt „weiß ich nicht" statt zu
  erfinden; führt keine Aktionen aus.

---

## 8. Konventionen (verbindlich)

Diese Prinzipien ziehen sich durch das ganze System — beim Bauen einhalten:

1. **Herkunft sichtbar.** Jede importierte/abgeleitete Größe trägt ihre Provenienz:
   `cvs.source`, `data_imports`, Marker wie `gsrc`/`rsrc`/`psrc` (geliefert/
   Rückmeldung/Plan), „gerechnet"-Kennzeichnung auf Berichtsfolien. Nie eine Zahl
   zeigen, ohne dass klar ist, woher sie kommt.
2. **Kein stiller Rückfall.** Keine erfundenen/Dummy-Daten bei leerem Ergebnis.
   Loads sind an den Login gekoppelt (sonst läuft RLS anonym ins Leere); echte
   Fehler werden sichtbar gemacht, nicht durch Fake-Fallbacks kaschiert. Kein
   Fallback vom CV-Skill auf den Projekt-Skill.
3. **Eine Wahrheit je Größe.** Nichts doppelt speichern: `position → category`
   abgeleitet; `contract.start` = einzige Eintritts-Wahrheit; Stundenlohn ergibt
   sich aus Monatsgehalt; KPIs über `kpi_id`; Schicht-/Verfügbarkeits-Regeln in
   geteilten Top-Level-Funktionen (`shiftEmpDayOk` …); `UPLOAD_SOURCES` eine Liste
   für Import + Upload-Plan. Bei Kennzahlen: Rankings/Aggregationen immer je Skill,
   nie über Skill-Grenzen.
4. **Zeitzonen:** lokale Daten mit `isoLocal()` bilden, nie `toISOString()` auf ein
   lokales `Date` (das kippt in MEZ auf den Vortag).
5. **Deploy ≠ Commit.** `deploy.sh` = rsync auf den Server (kein Git). Committen/
   Pushen nur auf ausdrückliche Aufforderung; nie „deployt und committed" melden,
   wenn nur deployt wurde. Build-ID-Stempel + Caddy-no-cache gegen Browser-Cache.
6. **Migrationen** liegen als SQL-Dateien in `migrations/`; der Betreiber spielt
   sie im Supabase-SQL-Editor ein. Secrets nie committen.
7. **Sichtbare Texte** ohne lange Gedankenstriche; Komma/Doppelpunkt/Punkt.

---

## 9. Bereichs-Überblick

Ein Absatz je Bereich (HR-Portal, sofern nicht anders vermerkt). Zur Orientierung,
nicht vollständig — Bedienung steht im Handbuch.

- **Cockpit** — Startbildschirm mit Kennzahlen-Kacheln, Forecast-vs-Ist, Marketing-,
  Upload- und Aufgaben-Kacheln. Daten aus KPIs/weekly_*/employees. **Wer:** alle
  HR-Portal-Rollen; Management sieht mehr. **Eigenheit:** pro Nutzer konfigurierbar
  (`jsr_user_cockpits_v1`), Management-only-Blöcke ausgeblendet für andere.
- **Mitarbeiter** — Mitarbeiter anlegen/pflegen über Reiter (Profil, Vertrag,
  Gehalt, Bank, HR, Hardware, Stunden, Projekt). Daten: `employees`. **Wer:**
  HR-Portal; Gehalt/Bank für Nicht-Admins RLS-maskiert. **Eigenheit:** eine Person
  = eine ID = ein Lebenszyklus; Gekündigte standardmäßig ausgeblendet.
- **Bewerber-Trichter** — Auswertung des Recruitings: kumulierte Reichweite je
  Phase, Abgänge, Herkunfts-Split (Meta/Sheet/übrige). Daten: `cvs` +
  `employees(source='cv')`. **Wer:** HR/Management. **Eigenheit:** Momentaufnahme
  nach Eingangsdatum, KEINE Statushistorie.
- **CV-Sync** — importiert Bewerber aus einem öffentlich veröffentlichten
  Google-Sheet (CSV, ohne Zugangsdaten). Daten: Sheet → `cvs` (source `Google
  Sheet`). **Wer:** HR/Management (System-Bereich). **Eigenheit:** Konfig in
  `jsr_cv_sync_config_v1`; läuft jetzt auch serverseitig (Edge Function
  `applicant-import`); Dedup über Telefon.
- **Schichtplanung** — einfacher Wochenplaner (Alltag) + „Workforce (Beta)" (nur
  HolidayCheck Sales). Daten: `shift_assignments`. **Wer:** Management + Projekt-
  leiter. **Eigenheit:** beide Tools teilen dieselbe Tabelle und die Prüf-Funktionen
  (`shiftEmpDayOk` …); unzulässige Optionen werden verhindert, nicht gemeldet;
  Öffnungszeiten je Projekt/Skill/Tag begrenzen hart.
- **Check-in** — Ist-Anwesenheit bestätigen. Daten: `shift_checkins` gegen
  `shift_assignments`. **Wer:** HR-Portal + Mitarbeiter-Portal. **Eigenheit:**
  reine Ist-Ebene, verglichen mit dem Plan.
- **Zeiterfassung** — Stempeln/Pausen. Daten: Schicht-/Pausendaten. **Wer:**
  HR-Portal. **Eigenheit:** „Vergleichsbetrieb" — Stempelung startet wirkungslos,
  der **Plan bleibt Abrechnungsgrundlage**; Pünktlichkeit erst mit echtem
  Stempelbetrieb.
- **Abwesenheiten** — Krank/Urlaub/Unbezahlt eintragen, Jahresübersicht,
  Kontingent. Daten: `employees.absences` (**jsonb-Array**) + Tabelle `absences`.
  **Wer:** HR. **Eigenheit:** `unpaid` kürzt das Gehalt anteilig; `vacation`/`sick`
  nicht; abwesend = nicht planbar.
- **Urlaubsanträge** — Anträge aus dem Mitarbeiter-Portal genehmigen/ablehnen/
  Gegenvorschlag. Daten: `jsr_vacation_requests_v1` → bei Freigabe wird eine
  Absence geschrieben. **Wer:** Management + Projektleiter (projektbezogen).
  **Eigenheit:** Ampel Grün/Gelb/Rot; Schutz bei Austritt (Zeitraum nach
  Austrittsdatum wird blockiert).
- **Kennzahlen** — Definition der KPIs je Projekt/Skill/Level. Daten: `kpi_config`.
  **Wer:** Management. **Eigenheit:** Kundenwert manuell gepflegt (nicht abgeleitet);
  immer über die `kpi_id`; Auswertungen strikt je Skill.
- **Performance** — Wochen-KPIs je Agent eintragen, Rangliste. Daten: `kpi_entries`.
  **Wer:** HR/Management. **Eigenheit:** welche KPIs erfasst werden, hängt am Skill;
  Ranking je Projekt+Skill.
- **Feedbackgespräche** — Mitarbeitergespräche mit versioniertem Fragenkatalog.
  Daten: `feedback_questions/sessions/answers`. **Wer:** HR/Management.
  **Eigenheit:** Snapshot-Versionierung (Antworten frieren den damaligen Katalog ein).
- **Call-Qualität** — Call-Stichproben je Kriterium bewerten. Daten:
  `call_criteria/samples/scores`. **Wer:** HR/Management, Anzeige auch beim Kunden.
  **Eigenheit:** zwei Achsen — offizieller Score (0 bei Compliance-Verstoß) vs.
  fachliche `raw_points`; Bogen je Projekt+Skill.
- **Schulungen** — Schulungen planen, Teilnehmer, Steckbrief; Timeline als Gantt.
  Daten: Schulungspläne. **Wer:** HR/Management. **Eigenheit:** Warnung bei offenen
  Plätzen kurz vor Start.
- **Organigramm** — Struktur je Projekt + „Unternehmensleitung". Daten: `org_nodes`
  (`project_id=NULL` = Firmenfunktionen). **Wer:** HR/Management. **Eigenheit:**
  Auto-Build aus Positionen + Drag&Drop; wächst im Browser, im PDF skaliert.
- **Kalender** — Termine, automatische Pflichttermine (z. B. Lohnlauf, Wechselkurs).
  Daten: `calendar_events`/`calendar_overrides`. **Wer:** HR/Management.
  **Eigenheit:** wiederkehrende Auto-Termine mit Erledigt-Merker je Vorkommen.
- **Präsentationen** — Kundenberichte (KW/Monat) erstellen und veröffentlichen.
  Daten: `presentations` + `report_*` + Deck (§6). **Wer:** Management +
  Projektleiter (projektbezogen). **Eigenheit:** geteilter Renderer; öffentliche
  Token-Seite + PDF; Look je Projekt.
- **Datenimport** — die Kundendateien hochladen (§5). Daten: → `weekly_*`,
  `kpi_*`, `report_*`. **Wer:** Management + Projektleiter. **Eigenheit:** Erkennung
  am Inhalt, `import_aliases`, Rohdatei in Storage, `data_imports`-Protokoll.
- **Upload-Plan** — je Projekt+Quelle Rhythmus/Fälligkeit/Kulanz/Zuständiger setzen.
  Daten: `upload_schedule` + `upload_project_owner`. **Wer:** Management-only.
  **Eigenheit:** die Ampel wird daraus live berechnet, nichts gespeichert.
- **Uploads** — Ampel „heute/diese Woche fällig / überfällig" + Projekt-Matrix
  „wer hängt hinterher". Daten: live aus Upload-Plan × Ziel-Daten × `data_imports`.
  **Wer:** Management (Matrix) + Projektleiter (eigene Liste), in EINEM Tab.
  **Eigenheit:** „Hochladen"-Sprung in den Datenimport; Aufgabe nur beim
  Zuständigen (Cockpit + Tagesaufgaben).
- **Recruiting Marketing** — Meta-Anzeigen (bezahlt) + Instagram (organisch),
  Ausgaben/Reichweite/Kosten je Bewerbung. Daten: `windsor_marketing` + `cvs`.
  **Wer:** Management-only. **Eigenheit:** CPA erst ab Kampagnenstart und nur mit
  `source='meta'` (echte Zuordnung); Herkunfts-Split.
- **Forecast** — Wochen-Forecast des Auftraggebers + „Forecast vs. Ist". Daten:
  `report_forecast` + `weekly_hours`. **Wer:** Management (+ Projektleiter); „vs.
  Ist" Management-only. **Eigenheit:** letzte vollständige Woche als Hauptwert,
  laufende nur als Hinweis.
- **Datenabfrage** — Fragen in Alltagssprache → SELECT (§7 `nlquery`). Daten: DB
  über `nlquery_ro`. **Wer:** Management-only. **Eigenheit:** ausschließlich lesend,
  Streaming, Klärung/„geht nicht", Datenbaum.
- **Dubletten** — Telefon-Kollisionen Meta ↔ Bestand entscheiden + Name+Datum-
  Gruppen putzen. Daten: `windsor_leads(status_review='dup')` + `cvs`. **Wer:**
  HR/Management. **Eigenheit:** kein Auto-Löschen, HR entscheidet je Paar.
- **Wissen** — Wissensbasis (Artikel) + „Wissen System" (Handbuch) + KI-Assistent
  (§7). Daten: `jsr_kb_v1`, `jsr_system_manual_v1`. **Wer:** alle HR-Portal-Nutzer.
  **Eigenheit:** der Assistent liest diese + Live-Fakten und sagt „weiß ich nicht"
  statt zu erfinden.
- **Löhne** — monatlicher Lohnlauf, Boni/Überstunden, Abrechnungen/Payslips. Daten:
  `jsr_payroll_v1` + `employees` + Boni. **Wer:** Management/Finance (HR sieht keine
  Management-Gehälter). **Eigenheit:** Monats-Zugehörigkeit **datumsgetrieben**
  (Eintritt/Austritt), Gehälter nativ in Fremdwährung, `unpaid`-Abzug automatisch.
- **Wirtschaftlichkeit** — je Projekt Umsatz gegen Kosten, Marge. Daten:
  Ist-Zahlen (`forecast.monthly_actuals`) + Personalkosten aus den Mitarbeiter-
  Datensätzen + Sach-/Raumkosten. **Wer:** Management/Finance (nicht HR).
  **Eigenheit:** zeigt nur Monate ab dem ersten mit sinnvollen Daten; Vollkosten-
  Basis + Währung sind offene Punkte.
- **Standorte** — Standorte und Raumkosten. Daten: Standortliste + `jsr_rk_*`
  (fix/variabel je Monat). **Wer:** Management/Finance. **Eigenheit:** Raumkosten
  zentral hier gepflegt (eine Wahrheit) und fließen in die Wirtschaftlichkeit;
  Remote-Standorte ohne Sitzplatz-Kennzahlen (offen).
- **App-Zugänge** — Login-Konten und Rollen verwalten. Daten: `app_users` +
  `roles_definitions`. **Wer:** Management (`is_admin`). **Eigenheit:**
  Letzter-Admin-Schutz (DB-Trigger); `client_id` für Kunden-Logins;
  kein Klartext-Passwort.
- **Kunden** — Kunden-Accounts und Client-Portal-Bereitstellung. Daten: Kunden +
  `app_users(role='kunde')`. **Wer:** Management. **Eigenheit:** Kundenlogin über
  Supabase-Auth + `client_id`; Client-Portal per RLS gehärtet (kein Zugriff auf
  Gehalt/Bank/fremde Daten).

---

## 10. Verweise

- **`CLAUDE.md`** — verbindliche fachliche Vorgaben und Änderungs-Regeln
  (Datenmodell, Feldnamen-Migration, Status-/Urlaubs-/Gehaltsmodell, offene
  technische Schulden). Bei Konflikten gilt CLAUDE.md.
- **Handbuch** — Bedienung (`SYSTEM_MANUAL` in `hr.html`, „Wissen System").
- **`supabase/schema_auth.sql`** — Rollen, RLS-Helfer, Guards.
- **`migrations/`** — alle DB-Änderungen als SQL.
- **`frontend/shared/presentation-slides.js`** — Berichts-Renderer.

*Lebendes Dokument — bei strukturellen Änderungen (neue Tabelle, neues Portal,
neue Import-Quelle, neue Konvention) hier nachziehen. Der KI-Assistent kennt eine
Kurzfassung dieses Aufbaus (Konstante `ARCHITEKTUR` in
`supabase/functions/assistant/index.ts`) — bei größeren Änderungen dort mitziehen.*
