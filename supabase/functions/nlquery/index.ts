// Edge Function: Datenabfrage per Sprache (Vorhaben 2).
// - Prueft, dass der Aufrufer Management ist (app_users.role_keys), sonst 403.
// - Baut das Schema hybrid: kuratierter Kern + Live-Glossar aus kpi_config und projects.
// - Fragt Claude; die Antwort ist ENTWEDER eine Rueckfrage (2-3 Optionen) ODER eine SELECT-Abfrage.
// - Fuehrt SELECTs ausschliesslich ueber die DB-Funktion nlquery_exec (Read-only-Rolle) aus.
// Deploy: supabase functions deploy nlquery ; Secret: supabase secrets set ANTHROPIC_API_KEY=...
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

// Kuratierter Schema-Kern (stabil, von Hand): Tabellen, wichtige Spalten, Konventionen.
const SCHEMA_CORE = `
Du hilfst, PostgreSQL-SELECT-Abfragen fuer ein BPO-Callcenter-CRM zu formulieren. NUR diese Tabellen sind
erlaubt (alles andere ist gesperrt): employees, kpi_config, kpi_entries, kpi_project_entries, weekly_hours,
weekly_calls, weekly_gauges, report_forecast, report_longterm, report_fte, report_measures, cvs, absences,
shift_assignments, call_criteria, call_samples, call_scores, windsor_marketing, projects.

Wichtige Strukturen und Konventionen:
- employees: Mitarbeiter. id (uuid), first_name, last_name, status (active|training|inactive|contract|
  terminated_* u.a.), position (Agent/Senior Agent/ASP/Supervisor/Teamleiter/Trainer/QM/Projektleiter/HR/
  Management/Finance/IT), project_id (text), project_skill (kleingeschrieben: 'sales'/'support'/...),
  location, fixed_salary, salary_currency, contract (jsonb: {start,end,signed_at,...}), absences (jsonb-Array:
  [{type:'vacation'|'sick'|'unpaid', from, to, days}]), bank (jsonb), work_hours. Skill IMMER kleinschreiben.
- projects: id (text), name, client, skills (jsonb), status. Projekt-Zuordnung ueber employees.project_id.
- kpi_config: Definition der Kennzahlen. id (text, z.B. 'kpi_1784709865565'), name, skill, project_id, type,
  unit, level ('agent'|'team'), thresholds (jsonb). Nutze diese Tabelle, um KPI-Ids zu benennen (siehe Glossar).
- kpi_entries: KPI-Wert JE AGENT je Woche. emp_id (uuid -> employees.id), kpi_id (-> kpi_config.id), value,
  kw, year, source. kpi_project_entries: KPI-Wert JE TEAM (project_id, skill, kpi_id, value, kw ODER month, year).
- weekly_hours: gelieferte Stunden je Mitarbeiter/Woche (project_id, employee_id, skill, kw, year, hours,
  sales_calls). weekly_calls: Call-Kennzahlen je Agent/Woche (project_id, employee_id, kw, year, answered,
  avg_handle_sec, avg_acw_sec, ...). weekly_gauges: CSAT je Agent/Woche (employee_id, kw, year, csat, anzahl).
- report_forecast: Auftraggeber-Forecast je Projekt/Skill/KW (fc_hours, planned_hours). report_longterm:
  12-Monats-Kapazitaetsmodell (rows jsonb). report_fte: FTE-Standard je Mitarbeiter (fte). report_measures:
  Massnahmen je Projekt/Skill (text, status, created_kw/year).
- cvs: Bewerber (Recruiting-Trichter). Felder u.a. name, status, source ('cv'/'instagram'/...), cv_date.
- shift_assignments: Schichtplan (employee_id, work_date, shift, net_hours).
- call_criteria/call_samples/call_scores: Call-Qualitaets-Bewertungen (Stichproben je Mitarbeiter,
  total_points, total_pct, raw_points, compliance_failed; call_samples.employee_id, sampled_date, kw, year).
- windsor_marketing: Recruiting-Marketing (date, datasource 'facebook'/'instagram', spend, impressions, reach).

Regeln:
- Erzeuge NUR ein einzelnes SELECT (oder WITH ... SELECT). Kein INSERT/UPDATE/DELETE/DDL, kein Semikolon.
- Nutze sprechende Spalten-Aliase (deutsch) in der Ergebnismenge.
- Datumsbezug ueber kw/year (ISO-Woche) bzw. month/year; fuer "letzte N Wochen"/Monate rechne mit kw/year.
- Bei Zeitreihen/Kategorien: schlage ein Diagramm vor (chart), sonst chart null.

DETERMINISMUS (wichtig): Formuliere fuer dieselbe oder bedeutungsgleiche Frage IMMER exakt dieselbe
Abfrage. Triff Standardannahmen fest und einheitlich; variiere Tabellenwahl, Joins, Aggregation und
Aliase nicht von Lauf zu Lauf. Waehle stets die einfachste kanonische Form. Halte dich dabei strikt an:
- Immer ein deterministisches ORDER BY mit eindeutigem Tie-Breaker (z.B. zusaetzlich nach id bzw. name),
  damit auch die Zeilenreihenfolge stabil ist.
- "Mitarbeiter" ohne Zusatz = ALLE Zeilen in employees, keine Status-Filterung. Nur filtern, wenn die
  Frage einen Status nennt ("aktive", "in Schulung", "gekuendigte" ...).
- "je Projekt" = GROUP BY employees.project_id, Projektname per JOIN auf projects.name. Analog "je Skill"
  ueber project_skill, "je Standort" ueber location.
- Zaehlungen mit count(*). Feste deutsche Aliase: anzahl, projekt, skill, standort, mitarbeiter, woche, monat.
- Kennzahlen (KPI) IMMER ueber die im Glossar genannte kpi_id ansprechen, nie ueber den Namen raten.
- Bei mehreren plausiblen Lesarten (Zeitraum? Kennzahl? Gliederung? Status?) NICHT raten, sondern mit
  action='clarify' rueckfragen. Lieber einmal praezisieren als bei jedem Lauf anders interpretieren.
`;

async function buildGlossary(sb: any): Promise<string> {
  try {
    const [{ data: kc }, { data: pr }] = await Promise.all([
      sb.from("kpi_config").select("id,name,skill,project_id,unit,level"),
      sb.from("projects").select("id,name,skills"),
    ]);
    const pn: Record<string, string> = {};
    (pr || []).forEach((p: any) => (pn[p.id] = p.name));
    const kpis = (kc || [])
      .map((k: any) => `- ${k.id} = "${k.name}" (${pn[k.project_id] || k.project_id || "global"}, Skill ${k.skill || "-"}, ${k.level || "agent"}${k.unit ? ", " + k.unit : ""})`)
      .join("\n");
    const projs = (pr || []).map((p: any) => `- ${p.id} = "${p.name}"`).join("\n");
    return `\nLIVE-GLOSSAR (aktuell aus der DB):\nKPI-Ids:\n${kpis || "(keine)"}\nProjekt-Ids:\n${projs || "(keine)"}\n`;
  } catch (_e) {
    return "";
  }
}

const RESPOND_TOOL = {
  name: "respond",
  description:
    "Antworte ENTWEDER mit einer Rueckfrage (action='clarify', 2-3 Optionen zum Anklicken) wenn die Frage " +
    "mehrdeutig ist (Zeitraum? Gliederung? Kennzahl?), ODER mit der fertigen SELECT-Abfrage (action='sql').",
  input_schema: {
    type: "object",
    properties: {
      action: { type: "string", enum: ["clarify", "sql"] },
      question: { type: "string", description: "Rueckfrage in Alltagssprache (nur bei clarify)" },
      options: { type: "array", items: { type: "string" }, description: "2-3 Antwortoptionen (nur bei clarify)" },
      sql: { type: "string", description: "Ein einzelnes SELECT/WITH (nur bei sql)" },
      explanation: { type: "string", description: "Ein Satz, was die Abfrage liefert (nur bei sql)" },
      chart: {
        type: ["object", "null"],
        properties: { type: { type: "string", enum: ["bar", "line"] }, x: { type: "string" }, y: { type: "string" } },
        description: "Diagramm-Vorschlag oder null",
      },
    },
    required: ["action"],
  },
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST erwartet" }, 405);

  const auth = req.headers.get("Authorization") || "";
  if (!auth) return json({ error: "Nicht angemeldet." }, 401);
  // Client mit dem JWT des Aufrufers -> RLS/Rollen greifen, auth.uid() ist gesetzt.
  const sb = createClient(SB_URL, ANON, { global: { headers: { Authorization: auth } } });

  // Management-Pruefung (serverseitig).
  const { data: udata } = await sb.auth.getUser();
  const uid = udata?.user?.id;
  if (!uid) return json({ error: "Sitzung ungueltig." }, 401);
  const { data: au } = await sb.from("app_users").select("role_keys").eq("user_id", uid).single();
  const roles: string[] = (au?.role_keys as string[]) || [];
  if (!roles.includes("management")) return json({ error: "Nur fuer Management freigegeben." }, 403);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "Ungueltiger Body." }, 400); }

  // Ausfuehrungs-Modus: fertiges SELECT ausfuehren (nach dem "Ausfuehren"-Klick). Braucht keinen KI-Schluessel.
  if (typeof body?.execute === "string" && body.execute.trim()) {
    const { data: rows, error } = await sb.rpc("nlquery_exec", { p_sql: body.execute });
    if (error) return json({ action: "result", error: error.message });
    return json({ action: "result", rows: rows || [] });
  }

  if (!ANTHROPIC_KEY) return json({ error: "ANTHROPIC_API_KEY ist noch nicht hinterlegt." }, 503);
  const messages = Array.isArray(body?.messages) ? body.messages : [];
  if (!messages.length) return json({ error: "Keine Frage uebergeben." }, 400);

  const system = SCHEMA_CORE + (await buildGlossary(sb));

  // Extrahiert den bisher gestreamten Wert des "sql"-Felds aus (unvollstaendigem) Tool-JSON.
  const extractSqlLive = (s: string): string | null => {
    const m = s.match(/"sql"\s*:\s*"/);
    if (!m) return null;
    let i = (m.index || 0) + m[0].length, out = "";
    while (i < s.length) {
      const c = s[i];
      if (c === "\\") {
        const n = s[i + 1];
        if (n === undefined) break; // unvollstaendige Escape-Sequenz am Puffer-Rand
        out += n === "n" ? "\n" : n === "t" ? "\t" : n === "r" ? "\r" : n === '"' ? '"' : n === "\\" ? "\\" : n === "/" ? "/" : n;
        i += 2; continue;
      }
      if (c === '"') break; // schliessendes Anfuehrungszeichen -> sql komplett
      out += c; i++;
    }
    return out;
  };

  // Claude STREAMEN (SSE), Antwort ueber das respond-Tool erzwingen, temperature 0 fuer Reproduzierbarkeit.
  // Die SQL wird waehrend des Eintreffens als NDJSON an den Browser weitergereicht (sql_delta), am Ende
  // kommt das autoritative Ergebnis (done/clarify).
  const enc = new TextEncoder();
  const stream = new ReadableStream({
    async start(controller) {
      const send = (o: unknown) => controller.enqueue(enc.encode(JSON.stringify(o) + "\n"));
      try {
        const resp = await fetch("https://api.anthropic.com/v1/messages", {
          method: "POST",
          headers: { "x-api-key": ANTHROPIC_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
          body: JSON.stringify({
            model: MODEL,
            max_tokens: 1500,
            stream: true,
            system,
            tools: [RESPOND_TOOL],
            tool_choice: { type: "tool", name: "respond" },
            messages: messages.map((m: any) => ({ role: m.role === "assistant" ? "assistant" : "user", content: String(m.content || "") })),
          }),
        });
        if (!resp.ok || !resp.body) {
          let msg = "KI-Fehler " + resp.status;
          try { const e = await resp.json(); msg = "KI-Fehler: " + (e?.error?.message || resp.status); } catch { /* egal */ }
          send({ t: "error", error: msg }); controller.close(); return;
        }
        const reader = resp.body.getReader();
        const dec = new TextDecoder();
        let buf = "", jsonAcc = "", sqlSent = 0;
        for (;;) {
          const { done, value } = await reader.read();
          if (done) break;
          buf += dec.decode(value, { stream: true });
          let idx: number;
          while ((idx = buf.indexOf("\n")) >= 0) {
            const line = buf.slice(0, idx); buf = buf.slice(idx + 1);
            if (!line.startsWith("data:")) continue;
            const payload = line.slice(5).trim();
            if (!payload || payload === "[DONE]") continue;
            let ev: any; try { ev = JSON.parse(payload); } catch { continue; }
            if (ev.type === "content_block_delta" && ev.delta?.type === "input_json_delta") {
              jsonAcc += ev.delta.partial_json || "";
              const live = extractSqlLive(jsonAcc);
              if (live != null && live.length > sqlSent) { send({ t: "sql_delta", v: live.slice(sqlSent) }); sqlSent = live.length; }
            }
          }
        }
        // Vollstaendiges Tool-JSON auswerten (autoritativ).
        let parsed: any = {};
        try { parsed = JSON.parse(jsonAcc); } catch { /* unvollstaendig */ }
        if (parsed.action === "clarify") {
          send({ t: "clarify", question: parsed.question || "Bitte praezisieren:", options: (parsed.options || []).slice(0, 3) });
        } else {
          const sql = String(parsed.sql || extractSqlLive(jsonAcc) || "").trim();
          if (!sql) send({ t: "error", error: "Keine Abfrage erzeugt." });
          else send({ t: "done", action: "sql", sql, explanation: parsed.explanation || "", chart: parsed.chart || null });
        }
      } catch (e) {
        send({ t: "error", error: "KI nicht erreichbar: " + (e as Error).message });
      }
      controller.close();
    },
  });
  return new Response(stream, { headers: { ...cors, "Content-Type": "application/x-ndjson" } });
});
