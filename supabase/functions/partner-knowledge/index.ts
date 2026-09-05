// Edge Function: Partner-Wissensspeicher (Antwort-Motor, Schnitt 2). Beantwortet Fragen zu einem Partner
// AUSSCHLIESSLICH aus dem hinterlegten Wissen (Register-Fakten + Dokument-Abschnitte), immer MIT Quelle.
// Grundregel: erfindet NICHTS. Steht die Antwort nicht drin -> known=false ("steht nicht drin"). Bei
// mehrdeutiger Frage fragt es zurück (rueckfrage) statt zu raten. Zugriff je Partner regelt kb_retrieve
// (auth.uid() + perm 'wissen') — die Function liest die Treffer über den User-Client (RLS/Perm greift).
// Deploy: supabase functions deploy partner-knowledge --use-api --no-verify-jwt
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

const ANTWORT_TOOL = {
  name: "antwort",
  description: "Deine Antwort an die Kollegin am Telefon. Nur aus dem gegebenen Wissen, immer mit Quelle.",
  input_schema: {
    type: "object",
    properties: {
      known: { type: "boolean", description: "true, wenn die Antwort im gegebenen Wissen steht; false, wenn nicht (dann NICHTS erfinden)" },
      answer: { type: "string", description: "die Antwort in 1-3 kurzen Sätzen (nur wenn known=true); sonst leer" },
      sources: { type: "array", items: { type: "string" }, description: "die genutzte(n) Fundstelle(n), wörtlich aus den eckigen Klammern des Wissens (Fakt-Label oder Dokumenttitel/Abschnitt)" },
      rueckfrage: { type: ["string", "null"], description: "wenn die Frage mehrdeutig ist (z. B. Transfer zum Hotel ODER zum Flughafen): die kurze Rückfrage statt zu raten; sonst null" },
    },
    required: ["known"],
  },
};

function factLine(f: any): string {
  const q = f.qualifier && typeof f.qualifier === "object" ? Object.entries(f.qualifier).filter(([, v]) => v).map(([k, v]) => k + ": " + v).join(", ") : "";
  const src = f.source === "manual" ? "manuell gepflegt" : (f.source_title || "Datei");
  const loc = f.source_locator ? ", " + f.source_locator : "";
  const gil = (f.valid_from || f.valid_to) ? (" [gültig " + (f.valid_from || "…") + " bis " + (f.valid_to || "offen") + "]") : "";
  const head = f.topic + (f.zielgebiet ? " / " + f.zielgebiet : "") + (q ? " (" + q + ")" : "");
  return "- [" + head + "] " + f.label + ": " + f.value + gil + "  (Quelle: " + src + loc + ")";
}
function chunkLine(c: any): string {
  return "- [" + (c.doc_title || "Dokument") + (c.section ? " / " + c.section : "") + "] " + String(c.content || "").slice(0, 800);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST erwartet" }, 405);
  const auth = req.headers.get("Authorization") || "";
  if (!auth) return json({ error: "Nicht angemeldet." }, 401);
  const sb = createClient(SB_URL, ANON, { global: { headers: { Authorization: auth } } });

  const { data: udata } = await sb.auth.getUser();
  if (!udata?.user?.id) return json({ error: "Sitzung ungültig." }, 401);

  let body: any = {}; try { body = await req.json(); } catch { /* egal */ }
  const question = String(body?.question || "").trim();
  const projectId = String(body?.project_id || "").trim();
  if (!question) return json({ error: "Keine Frage übergeben." }, 400);
  if (!projectId) return json({ error: "Kein Partner angegeben." }, 400);
  if (!ANTHROPIC_KEY) return json({ error: "Der KI-Schlüssel ist noch nicht hinterlegt." }, 503);

  // Treffer holen (RPC prüft Zugriff über auth.uid() + perm 'wissen')
  const { data: r, error: re } = await sb.rpc("kb_retrieve", { p_project: projectId, p_q: question, p_limit: 8 });
  if (re) return json({ error: "Suche fehlgeschlagen: " + re.message }, 502);
  if (!r || r.ok === false) return json({ error: "Kein Zugriff auf diesen Partner." }, 403);
  const facts: any[] = Array.isArray(r.facts) ? r.facts : [];
  const chunks: any[] = Array.isArray(r.chunks) ? r.chunks : [];

  // Nichts gefunden -> gar nicht erst die KI fragen. Ehrliche Fehlanzeige (spart Kosten, kein Erfinden).
  if (!facts.length && !chunks.length) {
    return json({ known: false, answer: "", sources: [], rueckfrage: null, note: "Dazu ist im Wissensspeicher nichts hinterlegt.", used: { facts: 0, chunks: 0 } });
  }

  const wissen = [
    facts.length ? "REGISTER-FAKTEN:\n" + facts.map(factLine).join("\n") : "",
    chunks.length ? "DOKUMENT-ABSCHNITTE:\n" + chunks.map(chunkLine).join("\n") : "",
  ].filter(Boolean).join("\n\n");

  const system =
    "Du bist ein Wissens-Assistent für ein Kundenprojekt. Eine Kollegin am Telefon stellt dir eine Frage. " +
    "Du antwortest wie ein hilfsbereiter Kollege: kurz, klar, auf den Punkt.\n\n" +
    "EISERNE REGELN:\n" +
    "- Antworte AUSSCHLIESSLICH aus dem WISSEN unten. Erfinde NICHTS, niemals, unter keinen Umständen.\n" +
    "- Steht die Antwort nicht im Wissen: known=false, answer leer. Lieber ehrlich \"steht nicht drin\" als eine geratene Auskunft.\n" +
    "- Bei Notfallnummern, Transferzeiten und Kontakten ist eine falsche Auskunft gefährlich. Im Zweifel known=false.\n" +
    "- Jede Antwort nennt in 'sources' die genutzte Fundstelle WÖRTLICH so, wie sie im Wissen in eckigen Klammern steht.\n" +
    "- Ist die Frage mehrdeutig (z. B. Transfer zum Hotel oder zum Flughafen; welche Saison; welcher Veranstalter), dann RATE NICHT: stelle in 'rueckfrage' die eine kurze Rückfrage, die du brauchst, und setze known=false.\n" +
    "- Gibt es je nach Saison/Veranstalter mehrere gültige Werte, nenne sie mit ihrer Unterscheidung, statt einen willkürlich zu wählen.\n" +
    "- Duze die Person. Keine Zusagen, keine Ausschmückung.\n\n" +
    "WISSEN (nur das zählt):\n" + wissen;

  let tool: any;
  try {
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": ANTHROPIC_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: MODEL, max_tokens: 800, system, tools: [ANTWORT_TOOL], tool_choice: { type: "tool", name: "antwort" }, messages: [{ role: "user", content: "FRAGE: " + question }] }),
    });
    const data = await resp.json();
    if (!resp.ok) return json({ error: "KI-Fehler: " + (data?.error?.message || resp.status) }, 502);
    tool = (data.content || []).find((c: any) => c.type === "tool_use");
    if (!tool) return json({ error: "Keine verwertbare Antwort." }, 502);
  } catch (e) {
    return json({ error: "Die KI ist gerade nicht erreichbar: " + (e as Error).message }, 502);
  }

  const out = tool.input || {};
  const known = out.known === true;
  return json({
    known,
    answer: known ? String(out.answer || "") : "",
    sources: Array.isArray(out.sources) ? out.sources : [],
    rueckfrage: (typeof out.rueckfrage === "string" && out.rueckfrage.trim()) ? out.rueckfrage.trim() : null,
    note: known ? "" : "Dazu ist im Wissensspeicher nichts (Eindeutiges) hinterlegt.",
    used: { facts: facts.length, chunks: chunks.length },
  });
});
