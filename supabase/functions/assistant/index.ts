// Edge Function: Wissens-Assistent (HR-Portal). Beantwortet "wie/wo"-Fragen aus dem hinterlegten Wissen.
// Zugang: jeder eingeloggte Nutzer mit HR-Portal-Zugang (roles_definitions.portals enthält 'hr').
// Wissen: Handbuch (app_config jsr_system_manual_v1) + Wissensbasis (jsr_kb_v1) + Live-Fakten aus der DB
// (Projekte, Uploads, Kennzahlen, Rollen) + kuratierte Navigations-Landkarte. NUR daraus antworten,
// sonst known=false ("weiß ich nicht"). Antwort: kurz, in Schritten, mit Sprung-Ziel. Keine Aktionen.
// Deploy: supabase functions deploy assistant  (Secret ANTHROPIC_API_KEY liegt schon).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

const MODEL = "claude-sonnet-5";
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Navigations-Landkarte (kuratiert): view-key = wo man was macht. Basis für "wo finde ich X" + Sprung-Ziel.
const NAV: string[][] = [
  ["start", "Start", "Einstieg/Begrüßung"],
  ["cockpit", "Cockpit", "Kennzahlen-Überblick, Kacheln"],
  ["daily_tasks", "Tagesaufgaben", "was heute zu erledigen ist"],
  ["employees", "Mitarbeiter", "Mitarbeiter anlegen/bearbeiten, Vertrag, Gehalt, Status, Kündigung"],
  ["absences", "Abwesenheiten", "Krank/Urlaub eintragen, Jahresübersicht, Kontingent"],
  ["urlaubantraege", "Urlaubsanträge", "Anträge der Mitarbeiter genehmigen/ablehnen/Gegenvorschlag"],
  ["payroll", "Löhne", "Lohnlauf erstellen, Boni/Überstunden, Abrechnungen"],
  ["performance", "Performance", "KPIs je Woche eintragen, Ranking"],
  ["callqa", "Call-Qualität", "Call-Bewertungen/Stichproben"],
  ["kanban", "Recruiting", "Bewerber-Pipeline (Phasen), per Drag&Drop weiterbewegen"],
  ["cvs", "CVs & Bewerber", "Bewerber-Liste, anlegen/bearbeiten, nächste Phase"],
  ["funnel", "Bewerber-Trichter", "Auswertung des Recruitings"],
  ["dubletten", "Dubletten", "doppelte Bewerber prüfen/entscheiden"],
  ["onboarding", "Onboarding", "Einarbeitungs-Checkliste, Hardware"],
  ["training_plans", "Schulungsplanung", "Schulungen planen, Teilnehmer bestätigen"],
  ["timeline", "Timeline", "Schulungen als Zeitleiste"],
  ["projects", "Projekte", "Projekt-Übersicht, Kennzahlen, Skills"],
  ["shiftplan", "Schichtplanung", "Wochen-Schichtplan"],
  ["checkin", "Check-in", "Ist-Anwesenheit bestätigen"],
  ["orgchart", "Organigramm", "Struktur je Projekt"],
  ["forecast", "Forecast", "Wochen-Forecast (Auftraggeber)"],
  ["praesentation", "Präsentationen", "Kundenbericht / Wochenbericht erstellen"],
  ["dataimport", "Datenimport", "Dateien hochladen (Rohdaten, Calls, Booking, Forecast, Langzeit)"],
  ["uploads", "Uploads", "Upload-Status: was heute/diese Woche fällig ist"],
  ["nlquery", "Datenabfrage", "Zahlen-Fragen an die Datenbank stellen"],
  ["feedback", "Feedbackgespräche", "Mitarbeitergespräche planen"],
  ["knowledge", "Wissensbasis", "Fach-Artikel nachschlagen"],
  ["wissen_system", "Wissen System", "dieses Handbuch"],
];
const NAV_KEYS = new Set(NAV.map((n) => n[0]));

// Aufbau des Systems (Kurzfassung von ARCHITEKTUR.md). Damit der Assistent nicht nur die Bedienung, sondern
// auch die Struktur kennt (Portale, Rollen, Datenzusammenhänge, Konventionen). Bei Änderungen an ARCHITEKTUR.md
// hier nachziehen.
const ARCHITEKTUR = `AUFBAU DES SYSTEMS (Struktur, nicht Bedienung):
PORTALE: HR-Portal (für Overhead/Admin), Mitarbeiter-Portal (Agenten mit eigenem Login), Client-Portal (Kunden).
Dazu öffentliche Token-Seiten (Präsentation, Showcase). Datenhaltung: Supabase (Postgres, Auth, Row-Level-Security,
Storage, Edge Functions).
ROLLEN (roles_definitions -> portals): kunde -> client; mitarbeiter -> mitarbeiter; teamlead/qm/trainer/asp/
projektleiter/hr/finance/management -> mitarbeiter+hr. Rechte über RLS-Helfer (is_management/is_hr/is_finance/
is_admin=mgmt|hr/is_planner/is_lead_only). Gehalt/Bank sind für Nicht-Admins geschützt; HR sieht keine
Management-Gehälter; Projektleiter sehen nur ihr Projekt; ein Last-Admin-Schutz verhindert das Aussperren.
DATENMODELL: Eine Person = eine ID = ein Lebenszyklus (nur der Status wechselt). Aus der Position wird die
Kategorie abgeleitet (agent/overhead/admin). Ein Projekt hat Skills. Die Projektzuweisung (Mitarbeiter ↔ Projekt
↔ Skill, mit Start/Ende) ist die operative Kernstruktur (KPIs, Schichten, Auswertungen laufen darüber).
CV-Skill (Selbstauskunft) ist NICHT der Projekt-Skill.
WICHTIGE EIGENHEITEN: Abwesenheiten liegen als jsonb-Feld am Mitarbeiter ({type,from,to,days}) und in der
Tabelle absences. Vertrag/Bank sind jsonb; contract.start ist die einzige Wahrheit für den Eintritt. Kennzahlen
immer über die kpi_id (nicht den Namen); kpi_entries = je Agent, kpi_project_entries = je Team. Bewerber tragen
ihre Herkunft in cvs.source (meta / Google Sheet / HR / cv / LP); Telefon ist eindeutig (eine Nummer, ein
Bewerber). app_config ist ein Schlüssel/Wert-Speicher für alle jsr_*-Konfigurationen.
IMPORTE: Erkennung am Inhalt, Datum aus der Datei, täglicher Upload ergänzt statt zu ersetzen, Rohdatei in den
Storage, Protokoll in data_imports. Rohdaten -> weekly_hours, Call-CSV -> weekly_calls, Gauges -> weekly_gauges,
Booking -> kpi_entries/kpi_project_entries, Forecast -> report_forecast, Langzeit -> report_longterm. Der
Bewerber-Import (Meta + Google-Sheet) läuft serverseitig täglich; Telefon-Dubletten werden zur Entscheidung
zurückgehalten, nicht automatisch gelöscht.
WOCHENBERICHT: ein Deck, gerendert aus KPIs/Wochendaten/Forecast/Maßnahmen; Sales- und Support-Teil; bei vielen
Personen brechen die Folien automatisch um; öffentliche Seite + PDF.
KONVENTIONEN: (1) Herkunft immer sichtbar. (2) Kein stiller Rückfall — keine erfundenen Daten, echte Fehler
sichtbar. (3) Eine Wahrheit je Größe (Kategorie abgeleitet, contract.start einzige Eintritts-Wahrheit, Kennzahl
über id, Auswertungen je Skill). Volltext: ARCHITEKTUR.md im Repo.`;
const UPLOAD_LABELS: Record<string, string> = { rohdaten: "Rohdaten-Excel", calls: "Call-CSV", gauges: "Gauges-Excel", booking_a: "Booking-Excel (Agent)", booking_week: "Booking-Team Woche", booking_month: "Booking-Team Monat", forecast_sales: "Forecast Sales", forecast_support: "Forecast Support", longterm: "Langzeit-Kapazität", mail: "Mail-Excel" };
const WEEKDAYS = ["", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"];

async function liveFacts(admin: any): Promise<string> {
  const parts: string[] = [];
  const pn: Record<string, string> = {};
  try { const { data } = await admin.from("projects").select("id,name"); (data || []).forEach((p: any) => (pn[p.id] = p.name)); if (data && data.length) parts.push("Projekte: " + data.map((p: any) => p.name).join(", ")); } catch (_e) { /* egal */ }
  try {
    const { data: us } = await admin.from("upload_schedule").select("project_id,source_type,cadence,due_weekday,active").eq("active", true);
    if (us && us.length) {
      const lines = us.map((u: any) => { const cad = u.cadence === "daily" ? "täglich" : u.cadence === "monthly" ? "monatlich" : u.cadence === "weekly_progressive" ? "mehrfach pro Woche" : "wöchentlich"; const day = u.due_weekday ? (" (fällig " + (WEEKDAYS[u.due_weekday] || "") + ")") : ""; return (UPLOAD_LABELS[u.source_type] || u.source_type) + " bei " + (pn[u.project_id] || u.project_id) + ": " + cad + day; });
      parts.push("Fällige Uploads (welche Datei wann):\n- " + lines.join("\n- "));
    }
  } catch (_e) { /* egal */ }
  try { const { data: kc } = await admin.from("kpi_config").select("name,skill,project_id"); if (kc && kc.length) parts.push("Kennzahlen: " + kc.map((k: any) => k.name + " (" + (pn[k.project_id] || k.project_id || "global") + ", " + (k.skill || "-") + ")").join(" · ")); } catch (_e) { /* egal */ }
  try { const { data: rd } = await admin.from("roles_definitions").select("role_key,label,portals"); if (rd && rd.length) parts.push("Rollen und ihre Portale: " + rd.map((r: any) => (r.label || r.role_key) + " → " + ((r.portals || []).join(", ") || "-")).join(" · ")); } catch (_e) { /* egal */ }
  return parts.join("\n\n");
}

const REPLY_TOOL = {
  name: "reply",
  description: "Deine Antwort an den Kollegen. Kurz, in Schritten, freundlich, in Alltagssprache.",
  input_schema: {
    type: "object",
    properties: {
      known: { type: "boolean", description: "true, wenn die Antwort im hinterlegten Wissen steht; false, wenn nicht (dann NICHTS erfinden)" },
      steps: { type: "array", items: { type: "string" }, description: "kurze Schritte, je ein Satz (nur wenn known=true)" },
      jump: { type: ["string", "null"], description: "view-key aus der NAVIGATION zum Hinspringen, oder null" },
      note: { type: "string", description: "ein kurzer Zusatz-Satz; bei known=false die freundliche Erklärung, dass dazu nichts hinterlegt ist" },
    },
    required: ["known"],
  },
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST erwartet" }, 405);
  const auth = req.headers.get("Authorization") || "";
  if (!auth) return json({ error: "Nicht angemeldet." }, 401);
  const sb = createClient(SB_URL, ANON, { global: { headers: { Authorization: auth } } });

  // Zugang: eingeloggter Nutzer mit HR-Portal (irgendeine Rolle, deren portals 'hr' enthält).
  const { data: udata } = await sb.auth.getUser();
  const uid = udata?.user?.id;
  if (!uid) return json({ error: "Sitzung ungültig." }, 401);
  const { data: au } = await sb.from("app_users").select("role_keys").eq("user_id", uid).single();
  const roles: string[] = (au?.role_keys as string[]) || [];
  if (!roles.length) return json({ error: "Kein Zugang." }, 403);
  const { data: rdefs } = await sb.from("roles_definitions").select("portals").in("role_key", roles);
  const hasHr = (rdefs || []).some((r: any) => (r.portals || []).includes("hr"));
  if (!hasHr) return json({ error: "Nur fürs HR-Portal freigegeben." }, 403);

  if (!ANTHROPIC_KEY) return json({ error: "Der KI-Schlüssel ist noch nicht hinterlegt." }, 503);
  let body: any = {}; try { body = await req.json(); } catch { /* egal */ }
  const messages = Array.isArray(body?.messages) ? body.messages : (body?.question ? [{ role: "user", content: String(body.question) }] : []);
  if (!messages.length) return json({ error: "Keine Frage übergeben." }, 400);

  // Wissen serverseitig laden (Service-Role, damit Fakten vollständig sind — es sind nur Metadaten).
  const admin = createClient(SB_URL, SERVICE);
  let manual: any[] = [], kb: any[] = [];
  try { const { data } = await admin.from("app_config").select("value").eq("key", "jsr_system_manual_v1").maybeSingle(); manual = (data && data.value) || []; } catch (_e) { /* egal */ }
  try { const { data } = await admin.from("app_config").select("value").eq("key", "jsr_kb_v1").maybeSingle(); kb = (data && data.value && data.value.articles) || []; } catch (_e) { /* egal */ }
  const facts = await liveFacts(admin);

  const manualText = (manual || []).map((d: any) => "### " + (d.title || "") + "\n" + ((d.sections || []).map((s: any) => "- " + (s.h || "") + ": " + (s.body || "")).join("\n"))).join("\n\n");
  const kbText = (kb || []).map((a: any) => "### " + (a.title || "") + (a.project_id ? " (" + a.project_id + ")" : "") + "\n" + (a.content || "")).join("\n\n");

  const system =
    "Du bist der interne Hilfe-Assistent eines HR-Systems. Du hilfst Kolleginnen und Kollegen, die das System benutzen, aber nicht auswendig kennen. Beantworte \"wie mache ich X\" und \"wo finde ich X\" wie ein hilfsbereiter Kollege.\n\n" +
    "REGELN:\n" +
    "- Antworte KURZ und in SCHRITTEN (je ein Satz), nicht als Aufsatz. Alltagssprache, keine Fachbegriffe.\n" +
    "- Wenn die Antwort einen Bereich betrifft, gib in 'jump' den passenden view-key aus der NAVIGATION-Liste an, damit der Nutzer direkt hinspringen kann. Sonst jump=null. NUR echte view-keys aus der Liste.\n" +
    "- Antworte AUSSCHLIESSLICH aus dem hinterlegten Wissen unten (Handbuch, Wissensbasis, Live-Fakten, Navigation). Findest du es dort NICHT, setze known=false und erfinde NICHTS — dann sagt das System dem Nutzer, dass dazu nichts hinterlegt ist und er Johannes fragen soll.\n" +
    "- Du führst NUR an und verweist, du führst KEINE Aktionen aus. Wer z. B. einen Mitarbeiter anlegt, soll das selbst tun.\n" +
    "- Zahlen-/Auswertungsfragen (\"wie viele …\") gehören nicht hierher: verweise auf den Bereich Datenabfrage (jump='nlquery', known=true, ein Satz).\n" +
    "- Fragen zum AUFBAU (\"wie ist das gebaut\", \"wie hängen die Daten zusammen\", \"wer sieht was\") beantwortest du aus dem Abschnitt AUFBAU — kurz, in Alltagssprache.\n\n" +
    ARCHITEKTUR + "\n\n" +
    "NAVIGATION (view-key = wo man was macht):\n" + NAV.map((n) => "- " + n[0] + " = " + n[1] + ": " + n[2]).join("\n") + "\n\n" +
    "LIVE-FAKTEN (aktuell aus der Datenbank):\n" + (facts || "(keine)") + "\n\n" +
    "HANDBUCH:\n" + (manualText || "(leer)") + "\n\n" +
    "WISSENSBASIS:\n" + (kbText || "(leer)");

  let tool: any;
  try {
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": ANTHROPIC_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: MODEL, max_tokens: 1000, system, tools: [REPLY_TOOL], tool_choice: { type: "tool", name: "reply" }, messages: messages.map((m: any) => ({ role: m.role === "assistant" ? "assistant" : "user", content: String(m.content || "") })) }),
    });
    const data = await resp.json();
    if (!resp.ok) return json({ error: "KI-Fehler: " + (data?.error?.message || resp.status) }, 502);
    tool = (data.content || []).find((c: any) => c.type === "tool_use");
    if (!tool) return json({ error: "Keine verwertbare Antwort." }, 502);
  } catch (e) {
    return json({ error: "Die KI ist gerade nicht erreichbar: " + (e as Error).message }, 502);
  }

  const out = tool.input || {};
  const known = out.known !== false;
  const jump = (typeof out.jump === "string" && NAV_KEYS.has(out.jump)) ? out.jump : null;
  return json({ known, steps: Array.isArray(out.steps) ? out.steps : [], jump, note: out.note || "" });
});
