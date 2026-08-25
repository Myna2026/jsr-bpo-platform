// Edge Function: KI-Hilfe fuer Besprechungsnotizen. Zwei Modi:
//   polish  -> Sprachkorrektur EINES Textes (Rechtschreibung/Grammatik/Stil), Inhalt/Sinn unveraendert.
//   digest  -> strukturierter Rollup ueber 1..N Besprechungen: was besprochen, was offen, was wiederholt sich,
//              plus Kurz-Zusammenfassung. Deckt Einzel-Analyse (eine Besprechung) UND Zeitraum (Woche/Monat/frei).
// Die Notizen kommen VOM Frontend (dort schon RLS-gelesen) — die Function liest keine Notiz-Tabellen, sie
// verarbeitet nur Text. Zugang wie der Assistent: eingeloggter Nutzer mit HR-Portal-Rolle. Secret ANTHROPIC_API_KEY.
// Deploy: supabase functions deploy meeting-notes-ai
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

const IMP_LABEL: Record<string, string> = { red: "wichtig", amber: "wichtiger", green: "in Ordnung" };

const POLISH_TOOL = {
  name: "polish",
  description: "Der sprachlich gesaeuberte Text.",
  input_schema: {
    type: "object",
    properties: { text: { type: "string", description: "der korrigierte Text, gleiche Bedeutung, gleiche Struktur (Stichpunkte bleiben Stichpunkte)" } },
    required: ["text"],
  },
};
const DIGEST_TOOL = {
  name: "digest",
  description: "Strukturierte Auswertung der Besprechungsnotizen.",
  input_schema: {
    type: "object",
    properties: {
      summary: { type: "string", description: "2-4 Saetze Kurz-Zusammenfassung in Alltagssprache" },
      besprochen: { type: "array", items: { type: "string" }, description: "die besprochenen Themen, je ein kurzer Punkt" },
      offen: { type: "array", items: { type: "string" }, description: "was noch offen/unerledigt ist" },
      wiederholt: { type: "array", items: { type: "string" }, description: "Themen, die ueber mehrere Besprechungen wiederkehren (leer bei nur einer Besprechung)" },
    },
    required: ["summary"],
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
  if (!roles.length) return json({ error: "Kein Zugang." }, 403);
  const { data: rdefs } = await sb.from("roles_definitions").select("portals").in("role_key", roles);
  const hasHr = (rdefs || []).some((r: any) => (r.portals || []).includes("hr"));
  if (!hasHr) return json({ error: "Nur fuers HR-Portal freigegeben." }, 403);

  if (!ANTHROPIC_KEY) return json({ error: "Der KI-Schluessel ist noch nicht hinterlegt." }, 503);
  let body: any = {}; try { body = await req.json(); } catch { /* egal */ }
  const mode = body.mode;

  let system = "", userText = "", tool = POLISH_TOOL;
  if (mode === "polish") {
    const text = String(body.text || "").trim();
    if (!text) return json({ error: "Kein Text uebergeben." }, 400);
    system = "Du korrigierst deutschsprachige Besprechungsnotizen sprachlich: Rechtschreibung, Grammatik, Zeichensetzung, klarer Stil. " +
      "Den INHALT und die BEDEUTUNG aenderst du NICHT, du erfindest nichts dazu und laesst nichts weg. Struktur bleibt: Stichpunkte bleiben Stichpunkte, Absaetze bleiben Absaetze. " +
      "Keine Anrede, keine Kommentare, keine Ueberschrift — gib nur den gesaeuberten Text zurueck.";
    userText = text;
    tool = POLISH_TOOL;
  } else if (mode === "digest") {
    const meetings = Array.isArray(body.meetings) ? body.meetings : [];
    if (!meetings.length) return json({ error: "Keine Besprechungen uebergeben." }, 400);
    const blocks = meetings.map((m: any) => {
      const items = Array.isArray(m.items) ? m.items : [];
      const il = items.map((it: any) => "  - [" + (it.done ? "erledigt" : "offen") + ", " + (IMP_LABEL[it.importance] || "") + "] " + String(it.text || "")).join("\n");
      return "## " + (m.date || "") + (m.title ? " — " + m.title : "") + (m.skill ? " (" + m.skill + ")" : "") + "\n" +
        (m.body ? String(m.body).trim() + "\n" : "") + (il ? "Punkte:\n" + il : "");
    }).join("\n\n");
    system = "Du wertest interne Besprechungsnotizen einer Overhead-Runde aus (Call-Center-Projekt). Fasse sachlich und knapp in Alltagssprache zusammen. " +
      "Nutze NUR was in den Notizen steht, erfinde nichts. Bei mehreren Besprechungen erkenne wiederkehrende Themen. " +
      "Offene Punkte sind die mit [offen]. Antworte auf Deutsch.";
    userText = (meetings.length === 1 ? "Analysiere diese Besprechung:\n\n" : "Fasse diese " + meetings.length + " Besprechungen zusammen:\n\n") + blocks;
    tool = DIGEST_TOOL;
  } else {
    return json({ error: "Unbekannter Modus." }, 400);
  }

  try {
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": ANTHROPIC_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: MODEL, max_tokens: 1500, system, tools: [tool], tool_choice: { type: "tool", name: tool.name }, messages: [{ role: "user", content: userText }] }),
    });
    const data = await resp.json();
    if (!resp.ok) return json({ error: "KI-Fehler: " + (data?.error?.message || resp.status) }, 502);
    const tu = (data.content || []).find((c: any) => c.type === "tool_use");
    if (!tu) return json({ error: "Keine verwertbare Antwort." }, 502);
    return json({ ok: true, ...(tu.input || {}) });
  } catch (e) {
    return json({ error: "Die KI ist gerade nicht erreichbar: " + (e as Error).message }, 502);
  }
});
