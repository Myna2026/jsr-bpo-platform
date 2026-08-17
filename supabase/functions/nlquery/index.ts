// Edge Function: Datenabfrage per Sprache.
// - Prueft, dass der Aufrufer Management ist (app_users.role_keys), sonst 403.
// - Schema hybrid: kuratierter Kern + Live-Glossar aus kpi_config/projects.
// - Fuehrt (clarify) ODER sagt was nicht geht (cannot) ODER erzeugt eine SELECT-Abfrage (sql).
// - SELECTs laufen ausschliesslich ueber die DB-Funktion nlquery_exec (Read-only-Rolle).
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

// Die 8 Bereiche des Datenbaums (Frontend nutzt dieselben Schluessel). Jede Tabelle gehoert zu einem Bereich.
const AREA_KEYS = ["mitarbeiter", "kennzahlen", "bewerber", "abwesenheiten", "schichten", "callqualitaet", "importe", "marketing"];

const SCHEMA_CORE = `
Du bist der Assistent einer "Datenabfrage per Sprache" fuer ein BPO-Callcenter-Unternehmen. Die Leute, die
dich benutzen, kennen KEIN SQL und KEINE Datenbank. Sie tippen eine Frage in Alltagssprache. Deine Aufgabe:
sie freundlich fuehren und am Ende eine korrekte PostgreSQL-SELECT-Abfrage bauen.

═══ SO SPRICHST DU (das Wichtigste) ═══
- IMMER ganze, freundliche Saetze. Nie Stichworte.
- NIE Fachbegriffe: keine "Aggregation", "Dimension", "Filter", "Datensatz", "Join", "Spalte", "Tabelle",
  "Gruppierung", "Query". Sprich von "je Projekt sehen", "alles zusammen", "diesen Monat", "aktive Leute".
- Statt "Nach welcher Dimension gruppieren?" -> "Willst du das je Projekt sehen oder alles zusammen?"
- Statt "Keine Datensaetze" -> "Dazu haben wir noch nichts erfasst."
- Massstab: Jemand sitzt zum ersten Mal davor und will nur wissen, wer diesen Monat oft krank war.

═══ DEINE DREI ANTWORT-WEGE ═══
1) action='clarify' — wenn die Frage MEHRDEUTIG ist, stelle EINE freundliche Rueckfrage (Feld question) mit
   2-4 konkreten Auswahl-Antworten (Feld options), jede in Alltagssprache. Frage SO LANGE nach, ueber mehrere
   Schritte, bis wirklich eindeutig ist, was gemeint ist. Beispiel "Wie viele Mitarbeiter?": frage
   "Meinst du alle zusammen, oder aufgeteilt?" -> Optionen "Alle zusammen", "Je Projekt", "Je Skill". Danach ggf.
   noch "Nur aktive Leute oder wirklich alle?". Lieber eine Rueckfrage zu viel als raten.
2) action='cannot' — wenn die Datenbank die Frage NICHT beantworten kann (die noetigen Daten gibt es nicht).
   Erklaere in ein, zwei Saetzen warum (Feld message, Alltagssprache), und biete 2-3 aehnliche Fragen an, die
   wir beantworten koennen (Feld alternatives).
3) action='sql' — die fertige Abfrage (Feld sql) + ein Satz in Alltagssprache, was herauskommt (explanation).
   Wenn die Frage zwar beantwortbar, aber WENIG AUSSAGEKRAEFTIG ist (z.B. ein Zeitraum, in dem noch keine
   Daten liegen; ein Durchschnitt aus nur zwei Werten), setze zusaetzlich 'warning' mit einem freundlichen
   Hinweis und einem besseren Vorschlag. Baue die Abfrage trotzdem.

IMMER (bei allen drei Wegen) 'areas' mitgeben: aus welchen Bereichen gelesen wird bzw. gelesen wuerde —
wenn moeglich GENAU als "bereich/unterbereich", sonst nur "bereich". Bereiche und Unterbereiche:
- mitarbeiter/stammdaten (employees Stammdaten), mitarbeiter/abwesenheiten (employees.absences),
  mitarbeiter/vertraege (contract, report_fte)
- kennzahlen/je_ma (kpi_entries, weekly_hours/calls/gauges), kennzahlen/je_projekt (kpi_project_entries,
  report_forecast), kennzahlen/konfig (kpi_config)
- bewerber/eingaenge (cvs), bewerber/meta (windsor_leads), bewerber/bewertungen (Tests/Status in cvs)
- abwesenheiten/urlaub, abwesenheiten/krankheit, abwesenheiten/unbezahlt (Tabelle absences nach type)
- schichten/plan (shift_assignments), schichten/checkin (shift_checkins)
- callqualitaet/bewertung (call_scores, call_samples), callqualitaet/kriterien (call_criteria)
- importe/uploads (data_imports), importe/zeitplan (upload_schedule)
- marketing/anzeigen (windsor_marketing Ausgaben), marketing/reichweite (windsor_marketing Reichweite)
Beispiel: "wer war diesen Monat krank" -> areas = ["abwesenheiten/krankheit","mitarbeiter/stammdaten"].

═══ WAS ES GIBT UND WO ES STEHT (nur diese Tabellen sind erlaubt) ═══
Bereich MITARBEITER:
- employees: alle Leute. id, first_name, last_name, status (active=aktiv, training=in Schulung, inactive=pausiert,
  contract=Vertrag unterschrieben, terminated_*=gekuendigt), position (Agent/Senior Agent/ASP/Supervisor/
  Teamleiter/Trainer/QM/Projektleiter/HR/Management/Finance/IT), project_id, project_skill (klein: 'sales'/
  'support'/...), location (Standort), fixed_salary, salary_currency, contract (jsonb: start/end/signed_at),
  work_hours. HINWEIS: Gehalt/Bank sind fuer manche Rollen maskiert — bei Geld-Fragen vorsichtig.
- projects: id, name, client, skills, status. Projektname immer aus projects.name (join ueber employees.project_id).
- report_fte: FTE-Standard je Mitarbeiter (project_id, employee_id, fte).
Bereich ABWESENHEITEN:
- absences: Abwesenheiten je Mitarbeiter (employee_id, type 'vacation'=Urlaub/'sick'=krank/'unpaid'=unbezahlt,
  from, to, days). Krankheitstage/Urlaubstage kommen VON HIER. "oft krank diesen Monat" = absences type='sick'
  im Monat je Mitarbeiter zaehlen/summieren.
Bereich KENNZAHLEN:
- kpi_config: Definition jeder Kennzahl. id (z.B. 'kpi_1784709865565'), name, skill, project_id, unit,
  level ('agent'=je Person, 'team'=je Team). Die richtige Kennzahl IMMER ueber die id aus dem Glossar unten,
  nie ueber den Namen raten.
- kpi_entries: Kennzahl-Wert JE PERSON je Woche (emp_id, kpi_id, value, kw, year).
- kpi_project_entries: Kennzahl-Wert JE TEAM (project_id, skill, kpi_id, value, kw ODER month, year).
- weekly_hours: gelieferte Stunden je Person/Woche (project_id, employee_id, skill, kw, year, hours, sales_calls).
- weekly_calls: Call-Zahlen je Person/Woche (employee_id, kw, year, answered, avg_handle_sec, avg_acw_sec).
- weekly_gauges: CSAT je Person/Woche (employee_id, kw, year, csat, anzahl).
- report_forecast (fc_hours/planned_hours je Projekt/Skill/KW), report_longterm (12-Monats-Modell, rows jsonb),
  report_measures (Massnahmen je Projekt/Skill).
Bereich BEWERBER:
- cvs: Bewerber im Recruiting-Trichter. first_name, last_name, status, source ('meta'=Anzeigen/'Google Sheet'/
  'HR'/...), cv_date, language_level, available_from. windsor_leads: Rohdaten der Meta-Bewerbungen.
Bereich SCHICHTEN:
- shift_assignments: Schichtplan (employee_id, work_date, shift, net_hours). shift_checkins: Ist-Anwesenheit.
Bereich CALLQUALITAET:
- call_criteria/call_samples/call_scores: Call-Bewertungen (call_samples.employee_id, sampled_date, kw, year,
  total_pct, raw_points, compliance_failed).
Bereich IMPORTE:
- data_imports: Protokoll der Datei-Importe (project_id, source_type, kw, year, status, created_at).
- upload_schedule: welche Datei in welchem Rhythmus faellig ist.
Bereich MARKETING:
- windsor_marketing: Recruiting-Werbung (date, datasource 'facebook'/'instagram', spend, impressions, reach).

Was es NICHT gibt (dann action='cannot'): Umsatz/Gewinn/Buchhaltung, einzelne Chat-Nachrichten, Lohnabrechnungen,
Anwesenheit in Echtzeit, alles was oben nicht steht.

═══ REGELN FUER DIE ABFRAGE ═══
- NUR ein einzelnes SELECT (oder WITH ... SELECT). Kein Schreiben, kein Semikolon.
- Ergebnis-Spalten mit deutschen, sprechenden Namen (z.B. mitarbeiter, projekt, anzahl, krankheitstage).
- Zeitbezug ueber kw/year (ISO-Woche) bzw. month/year; Datumsspalten (from/to, cv_date, work_date, date) direkt.
- Immer ein festes ORDER BY mit eindeutigem Zweit-Kriterium (z.B. zusaetzlich nach name), damit die Reihenfolge
  stabil ist. Fuer dieselbe Frage IMMER dieselbe Abfrage bauen (kanonische, einfachste Form).
- "Mitarbeiter" ohne Zusatz = alle Zeilen in employees, kein Status-Filter (nur filtern, wenn ein Status genannt
  ist). "je Projekt" ueber project_id + join projects.name; "je Skill" ueber project_skill; "je Standort" ueber location.
- Bei Zeitreihe/Kategorien einen Diagramm-Vorschlag (chart) geben, sonst chart null.
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
    return `\nLIVE-GLOSSAR (aktuell aus der DB) — nutze diese echten Kennungen statt zu raten:\nKennzahlen:\n${kpis || "(keine)"}\nProjekte:\n${projs || "(keine)"}\n`;
  } catch (_e) {
    return "";
  }
}

const RESPOND_TOOL = {
  name: "respond",
  description:
    "Antworte in EINFACHER Alltagssprache, ganze Saetze, keine Fachbegriffe. Drei Wege: action='clarify' " +
    "(freundliche Rueckfrage question + 2-4 Optionen, so lange bis eindeutig), action='cannot' (message warum " +
    "es nicht geht + 2-3 alternatives), action='sql' (sql + explanation, optional warning wenn wenig " +
    "aussagekraeftig). IMMER areas mitgeben (Bereiche, aus denen gelesen wird).",
  input_schema: {
    type: "object",
    properties: {
      action: { type: "string", enum: ["clarify", "sql", "cannot"] },
      question: { type: "string", description: "Freundliche Rueckfrage in ganzen Saetzen (nur clarify)" },
      options: { type: "array", items: { type: "string" }, description: "2-4 konkrete Auswahl-Antworten in Alltagssprache (nur clarify)" },
      message: { type: "string", description: "Ganze Saetze, warum es nicht geht (nur cannot)" },
      alternatives: { type: "array", items: { type: "string" }, description: "2-3 aehnliche, beantwortbare Fragen (nur cannot)" },
      sql: { type: "string", description: "Ein einzelnes SELECT/WITH (nur sql)" },
      explanation: { type: "string", description: "Ein Satz in Alltagssprache, was herauskommt (nur sql)" },
      warning: { type: ["string", "null"], description: "Optionaler Hinweis, wenn die Antwort wenig aussagekraeftig ist, mit besserem Vorschlag (nur sql)" },
      chart: {
        type: ["object", "null"],
        properties: { type: { type: "string", enum: ["bar", "line"] }, x: { type: "string" }, y: { type: "string" } },
        description: "Diagramm-Vorschlag oder null",
      },
      areas: { type: "array", items: { type: "string" }, description: "Bereiche/Unterbereiche, aus denen gelesen wird — bevorzugt 'bereich/unterbereich' (siehe System-Text), sonst 'bereich'" },
    },
    required: ["action"],
  },
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST erwartet" }, 405);

  const auth = req.headers.get("Authorization") || "";
  if (!auth) return json({ error: "Nicht angemeldet." }, 401);
  const sb = createClient(SB_URL, ANON, { global: { headers: { Authorization: auth } } });

  const { data: udata } = await sb.auth.getUser();
  const uid = udata?.user?.id;
  if (!uid) return json({ error: "Sitzung ungueltig." }, 401);
  const { data: au } = await sb.from("app_users").select("role_keys").eq("user_id", uid).single();
  const roles: string[] = (au?.role_keys as string[]) || [];
  if (!roles.includes("management")) return json({ error: "Nur fuer Management freigegeben." }, 403);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "Ungueltiger Body." }, 400); }

  if (typeof body?.execute === "string" && body.execute.trim()) {
    const { data: rows, error } = await sb.rpc("nlquery_exec", { p_sql: body.execute });
    if (error) return json({ action: "result", error: error.message });
    return json({ action: "result", rows: rows || [] });
  }

  if (!ANTHROPIC_KEY) return json({ error: "Der KI-Schluessel ist noch nicht hinterlegt." }, 503);
  const messages = Array.isArray(body?.messages) ? body.messages : [];
  if (!messages.length) return json({ error: "Keine Frage uebergeben." }, 400);

  const system = SCHEMA_CORE + (await buildGlossary(sb));

  const extractSqlLive = (s: string): string | null => {
    const m = s.match(/"sql"\s*:\s*"/);
    if (!m) return null;
    let i = (m.index || 0) + m[0].length, out = "";
    while (i < s.length) {
      const c = s[i];
      if (c === "\\") { const n = s[i + 1]; if (n === undefined) break;
        out += n === "n" ? "\n" : n === "t" ? "\t" : n === "r" ? "\r" : n === '"' ? '"' : n === "\\" ? "\\" : n === "/" ? "/" : n;
        i += 2; continue; }
      if (c === '"') break;
      out += c; i++;
    }
    return out;
  };
  // Zieht das vollstaendige "areas":[...]-Array aus dem (noch unvollstaendigen) Tool-JSON, sobald es geschlossen ist.
  const extractAreas = (s: string): string[] | null => {
    const m = s.match(/"areas"\s*:\s*\[/);
    if (!m) return null;
    const start = (m.index || 0) + m[0].length - 1;
    const close = s.indexOf("]", start);
    if (close < 0) return null;
    try { const arr = JSON.parse(s.slice(start, close + 1)); return Array.isArray(arr) ? arr : null; } catch { return null; }
  };

  const enc = new TextEncoder();
  const stream = new ReadableStream({
    async start(controller) {
      const send = (o: unknown) => controller.enqueue(enc.encode(JSON.stringify(o) + "\n"));
      try {
        const resp = await fetch("https://api.anthropic.com/v1/messages", {
          method: "POST",
          headers: { "x-api-key": ANTHROPIC_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
          body: JSON.stringify({
            model: MODEL, max_tokens: 1600, stream: true, system,
            tools: [RESPOND_TOOL], tool_choice: { type: "tool", name: "respond" },
            messages: messages.map((m: any) => ({ role: m.role === "assistant" ? "assistant" : "user", content: String(m.content || "") })),
          }),
        });
        if (!resp.ok || !resp.body) {
          let msg = "Die KI hat nicht geantwortet.";
          try { const e = await resp.json(); msg = "KI-Fehler: " + (e?.error?.message || resp.status); } catch { /* egal */ }
          send({ t: "error", error: msg }); controller.close(); return;
        }
        const reader = resp.body.getReader();
        const dec = new TextDecoder();
        let buf = "", jsonAcc = "", sqlSent = 0, areasSent = false;
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
              if (!areasSent) { const ar = extractAreas(jsonAcc); if (ar) { send({ t: "areas", v: ar }); areasSent = true; } }
              const live = extractSqlLive(jsonAcc);
              if (live != null && live.length > sqlSent) { send({ t: "sql_delta", v: live.slice(sqlSent) }); sqlSent = live.length; }
            }
          }
        }
        let parsed: any = {};
        try { parsed = JSON.parse(jsonAcc); } catch { /* unvollstaendig */ }
        if (!areasSent && Array.isArray(parsed.areas)) send({ t: "areas", v: parsed.areas });
        if (parsed.action === "clarify") {
          send({ t: "clarify", question: parsed.question || "Kannst du das noch etwas genauer sagen?", options: (parsed.options || []).slice(0, 4) });
        } else if (parsed.action === "cannot") {
          send({ t: "cannot", message: parsed.message || "Das laesst sich mit unseren Daten nicht beantworten.", alternatives: (parsed.alternatives || []).slice(0, 3) });
        } else {
          const sql = String(parsed.sql || extractSqlLive(jsonAcc) || "").trim();
          if (!sql) send({ t: "error", error: "Ich konnte dazu keine Abfrage bauen. Formulier die Frage bitte etwas anders." });
          else send({ t: "done", action: "sql", sql, explanation: parsed.explanation || "", warning: parsed.warning || null, chart: parsed.chart || null, areas: Array.isArray(parsed.areas) ? parsed.areas : [] });
        }
      } catch (e) {
        send({ t: "error", error: "Die KI ist gerade nicht erreichbar: " + (e as Error).message });
      }
      controller.close();
    },
  });
  return new Response(stream, { headers: { ...cors, "Content-Type": "application/x-ndjson" } });
});
