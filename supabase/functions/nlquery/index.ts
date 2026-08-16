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

  // Claude aufrufen, Antwort ueber das respond-Tool erzwingen.
  let tool: any;
  try {
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": ANTHROPIC_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 1500,
        system,
        tools: [RESPOND_TOOL],
        tool_choice: { type: "tool", name: "respond" },
        messages: messages.map((m: any) => ({ role: m.role === "assistant" ? "assistant" : "user", content: String(m.content || "") })),
      }),
    });
    const data = await resp.json();
    if (!resp.ok) return json({ error: "KI-Fehler: " + (data?.error?.message || resp.status) }, 502);
    tool = (data.content || []).find((c: any) => c.type === "tool_use");
    if (!tool) return json({ error: "Keine verwertbare KI-Antwort." }, 502);
  } catch (e) {
    return json({ error: "KI nicht erreichbar: " + (e as Error).message }, 502);
  }

  const out = tool.input || {};
  if (out.action === "clarify") {
    return json({ action: "clarify", question: out.question || "Bitte praezisieren:", options: (out.options || []).slice(0, 3) });
  }
  // action === 'sql' — SQL nur ZURUECKGEBEN (sichtbar, bevor es laeuft). Ausfuehren erst ueber den execute-Modus.
  const sql = String(out.sql || "").trim();
  if (!sql) return json({ error: "Keine Abfrage erzeugt." }, 502);
  return json({ action: "sql", sql, explanation: out.explanation || "", chart: out.chart || null });
});
