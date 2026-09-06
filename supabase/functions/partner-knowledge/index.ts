// Edge Function: Partner-Wissensspeicher (Antwort-Motor). Beantwortet Fragen zu einem Partner AUSSCHLIESSLICH
// aus dem hinterlegten Wissen (Register-Fakten + Dokument-Abschnitte), immer MIT Quelle. Grundregel: erfindet
// NICHTS. Steht nichts drin -> known=false. Bei mehrdeutiger Frage: rueckfrage statt raten.
// Schnitt 8: STRUKTURIERTE Antwort. Die KI (a) erkennt den Blickwinkel (anleitung = Kunde am Telefon braucht
// Handlungsschritte / erklaerung), (b) gliedert verschiedene Sachverhalte in blocks (schritt/hinweis/notfall/
// info), (c) denkt mit: schlägt verwandte, ungefragte Punkte vor (related) — nur aus echtem Wissen.
// Zugriff je Partner regelt kb_retrieve (auth.uid() + perm 'wissen'). Deploy: supabase functions deploy partner-knowledge --use-api --no-verify-jwt
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

// Jede Frage protokollieren (Lern-Mechanik): Lücken-Liste, häufige Fragen, "war falsch"-Rückmeldung.
async function logQuery(projectId: string, uid: string, question: string, r: any): Promise<string | null> {
  try {
    const admin = createClient(SB_URL, SERVICE);
    const answerText = r.known
      ? [r.title, ...(Array.isArray(r.blocks) ? r.blocks.map((b: any) => (b.title ? b.title + ": " : "") + b.text) : [])].filter(Boolean).join(" | ")
      : null;
    const { data } = await admin.from("kb_queries").insert({
      project_id: projectId, user_id: uid, question, known: !!r.known, had_rueckfrage: !!r.rueckfrage,
      fact_count: (r.used && r.used.facts) || 0, chunk_count: (r.used && r.used.chunks) || 0,
      answer: answerText, sources: Array.isArray(r.sources) && r.sources.length ? r.sources : null,
    }).select("id").single();
    return data?.id || null;
  } catch (_e) { return null; }
}

const ANTWORT_TOOL = {
  name: "antwort",
  description: "Deine gegliederte Antwort an die Kollegin am Telefon. Nur aus dem gegebenen Wissen, mit Quelle je Block.",
  input_schema: {
    type: "object",
    properties: {
      known: { type: "boolean", description: "true, wenn die Antwort im Wissen steht; false, wenn nicht (dann nichts erfinden)" },
      intent: { type: "string", enum: ["anleitung", "erklaerung"], description: "anleitung = die Person (oder ihr Kunde am Telefon) steht in einer Situation und braucht Handlungsschritte; erklaerung = sie will verstehen, wie etwas abläuft" },
      title: { type: "string", description: "kurze Überschrift der Antwort (wenige Worte), das Wichtigste zuerst" },
      blocks: {
        type: "array",
        description: "die Antwort in getrennte Sachverhalte gegliedert, in sinnvoller Reihenfolge (Wichtigstes/erster Schritt oben)",
        items: {
          type: "object",
          properties: {
            kind: { type: "string", enum: ["schritt", "hinweis", "notfall", "info"], description: "schritt = konkrete Handlung; notfall = was tun, wenn es schiefgeht / Notfallkontakt; hinweis = wichtiger Zusatz; info = erklärender Teil" },
            title: { type: ["string", "null"], description: "kurzer Titel des Blocks, optional" },
            text: { type: "string", description: "der Inhalt, kurz und klar" },
            source: { type: ["string", "null"], description: "Fundstelle wörtlich aus den eckigen Klammern des Wissens" },
          },
          required: ["kind", "text"],
        },
      },
      related: {
        type: "array",
        description: "verwandte Punkte, nach denen NICHT gefragt wurde, die aber wahrscheinlich als Nächstes gebraucht werden. NUR wenn die Antwort darauf im Wissen (auch im Abschnitt VERWANDT) steht. Sonst leer.",
        items: {
          type: "object",
          properties: {
            label: { type: "string", description: "kurzes Angebot, z. B. 'Nummer der Agentur' oder 'Regel bei verspäteten Flügen'" },
            question: { type: "string", description: "die vollständige Frage, die gestellt wird, wenn man draufklickt" },
          },
          required: ["label", "question"],
        },
      },
      rueckfrage: { type: ["string", "null"], description: "wenn die Frage mehrdeutig ist: die kurze Rückfrage statt zu raten (dann known=false, blocks leer); sonst null" },
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
function relatedLine(f: any): string {
  const head = f.topic + (f.zielgebiet ? " / " + f.zielgebiet : "");
  return "- [" + head + "] " + f.label + ": " + f.value;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST erwartet" }, 405);
  const auth = req.headers.get("Authorization") || "";
  if (!auth) return json({ error: "Nicht angemeldet." }, 401);
  const sb = createClient(SB_URL, ANON, { global: { headers: { Authorization: auth } } });

  const { data: udata } = await sb.auth.getUser();
  if (!udata?.user?.id) return json({ error: "Sitzung ungültig." }, 401);
  const uid = udata.user.id;

  let body: any = {}; try { body = await req.json(); } catch { /* egal */ }
  const question = String(body?.question || "").trim();
  const projectId = String(body?.project_id || "").trim();
  if (!question) return json({ error: "Keine Frage übergeben." }, 400);
  if (!projectId) return json({ error: "Kein Partner angegeben." }, 400);
  if (!ANTHROPIC_KEY) return json({ error: "Der KI-Schlüssel ist noch nicht hinterlegt." }, 503);

  const { data: r, error: re } = await sb.rpc("kb_retrieve", { p_project: projectId, p_q: question, p_limit: 8 });
  if (re) return json({ error: "Suche fehlgeschlagen: " + re.message }, 502);
  if (!r || r.ok === false) return json({ error: "Kein Zugriff auf diesen Partner." }, 403);
  const facts: any[] = Array.isArray(r.facts) ? r.facts : [];
  const chunks: any[] = Array.isArray(r.chunks) ? r.chunks : [];
  const related: any[] = Array.isArray(r.related) ? r.related : [];

  // Partner-Agent (Name + Charakter) für Ton und Begrüßung. Nicht sensibel; RLS erlaubt select für Angemeldete.
  const { data: pa } = await sb.from("partner_agents").select("name,character").eq("project_id", projectId).maybeSingle();
  const agentName = (pa && pa.name) || "der Kollege";
  const persona = (pa && pa.character) || "";
  const MISS = "Da muss ich passen, das steht dazu nicht in meinen Unterlagen.";

  // Nichts gefunden -> gar nicht erst die KI fragen. Ehrliche Fehlanzeige (spart Kosten, kein Erfinden).
  if (!facts.length && !chunks.length && !related.length) {
    const res: any = { known: false, intent: "erklaerung", title: "", blocks: [], related: [], sources: [], rueckfrage: null, note: MISS, used: { facts: 0, chunks: 0 } };
    res.query_id = await logQuery(projectId, uid, question, res);
    return json(res);
  }

  const wissen = [
    facts.length ? "REGISTER-FAKTEN:\n" + facts.map(factLine).join("\n") : "",
    chunks.length ? "DOKUMENT-ABSCHNITTE:\n" + chunks.map(chunkLine).join("\n") : "",
    related.length ? "VERWANDT (nicht gefragt, aber evtl. als Nächstes nützlich — nur hieraus related vorschlagen):\n" + related.map(relatedLine).join("\n") : "",
  ].filter(Boolean).join("\n\n");

  const system =
    "Du bist " + agentName + ", ein Kollege im Call-Center-Team. " + (persona ? persona + " " : "") +
    "Eine Kollegin stellt dir eine Frage, oft während ein Kunde am Telefon ist. Antworte in deinem Ton, wie dieser Kollege, aber immer knapp und klar.\n\n" +
    "EISERNE REGELN:\n" +
    "- Antworte AUSSCHLIESSLICH aus dem WISSEN unten. Erfinde NICHTS, niemals — keine erfundene Nummer, Zeit oder Adresse.\n" +
    "- Deckt das Wissen die Frage ab (auch teilweise), dann ANTWORTE (known=true) und nenne die Quelle. known=false NUR, wenn das Wissen die Frage wirklich nicht enthält. Die Vorsicht bei Nummern/Zeiten bedeutet: nichts erfinden — NICHT: eine vorhandene Auskunft verweigern.\n" +
    "- Die Abschnitte können mehrere Zielgebiete/Fälle enthalten (die Unterlagen sind oft Tabellen mit einer Zeile je Ort). Nutze nur die Zeile(n), die zum gefragten Ort/Fall passen; ist der gefragte Ort dabei, beantworte die Frage daraus.\n" +
    "- Mehrdeutige Frage (Hotel oder Flughafen; welche Saison; welcher Veranstalter): known=false und stelle in 'rueckfrage' die eine nötige Rückfrage, statt zu raten.\n\n" +
    "SO ANTWORTEST DU (wenn known=true):\n" +
    "- BLICKWINKEL erkennen: Beschreibt die Frage eine Situation (\"Der Kunde findet seinen Transfer nicht\")? -> intent=anleitung, gib konkrete Handlungsschritte (kind='schritt'). Will sie verstehen, wie etwas abläuft (\"Wie läuft der Transfer ab\")? -> intent=erklaerung, erkläre (kind='info').\n" +
    "- GLIEDERN: Trenne verschiedene Sachverhalte in einzelne blocks. Was zusammengehört, in einen Block; was verschieden ist, in eigene. Das Wichtigste bzw. der erste Schritt zuerst.\n" +
    "- Was tun, wenn es schiefgeht (niemand da, Notfallkontakt): eigener Block kind='notfall'.\n" +
    "- Jeder Block nennt in 'source' die Fundstelle wörtlich aus den eckigen Klammern.\n" +
    "- MITDENKEN: Schlage in 'related' 0-3 verwandte Punkte vor, nach denen nicht gefragt wurde, die aber gleich gebraucht werden — NUR wenn ihre Antwort im WISSEN (v. a. Abschnitt VERWANDT) steht. Nichts erfinden.\n" +
    "- Kurz, klar, telefontauglich. Duze die Person. Keine Zusagen, keine Ausschmückung.\n\n" +
    "WISSEN (nur das zählt):\n" + wissen;

  let tool: any;
  try {
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": ANTHROPIC_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: MODEL, max_tokens: 1300, system, tools: [ANTWORT_TOOL], tool_choice: { type: "tool", name: "antwort" }, messages: [{ role: "user", content: "FRAGE: " + question }] }),
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
  const blocks = known && Array.isArray(out.blocks)
    ? out.blocks.filter((b: any) => b && b.text).map((b: any) => ({
        kind: ["schritt", "hinweis", "notfall", "info"].includes(b.kind) ? b.kind : "info",
        title: (b.title && String(b.title).trim()) || null,
        text: String(b.text).trim(),
        source: (b.source && String(b.source).trim()) || null,
      }))
    : [];
  const relatedOut = known && Array.isArray(out.related)
    ? out.related.filter((x: any) => x && x.label && x.question).slice(0, 3).map((x: any) => ({ label: String(x.label).trim(), question: String(x.question).trim() }))
    : [];
  const sources = [...new Set(blocks.map((b: any) => b.source).filter(Boolean))];
  const res: any = {
    known,
    intent: out.intent === "anleitung" ? "anleitung" : "erklaerung",
    title: known ? String(out.title || "").trim() : "",
    blocks,
    related: relatedOut,
    sources,
    rueckfrage: (typeof out.rueckfrage === "string" && out.rueckfrage.trim()) ? out.rueckfrage.trim() : null,
    note: known ? "" : MISS,
    used: { facts: facts.length, chunks: chunks.length },
  };
  res.query_id = await logQuery(projectId, uid, question, res);
  return json(res);
});
