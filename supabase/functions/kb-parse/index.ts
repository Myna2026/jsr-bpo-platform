// Edge Function: kb-parse (Wissensspeicher Schnitt 4). Extrahiert Text aus PDF und Word (.docx) und liefert
// durchsuchbare Abschnitte zurück — genau wie die clientseitige Excel/CSV/Text-Zerlegung, nur für die Formate,
// die der Browser nicht selbst kann. Speichert NICHTS: nur parsen, Client zeigt Vorschau und speichert wie bei S1.
// PDF: unpdf (pdf.js, serverless-tauglich) mit Seitenzahlen. DOCX: entpacken (fflate) + word/document.xml auslesen.
// Deploy: supabase functions deploy kb-parse --use-api --no-verify-jwt
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { extractText, getDocumentProxy } from "https://esm.sh/unpdf@0.12.1";
import { unzipSync, strFromU8 } from "https://esm.sh/fflate@0.8.2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const MAXC = 1500;

function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
// Absätze in Abschnitte bis MAXC Zeichen packen (Absatzgrenzen wahren, überlange Absätze hart schneiden).
function packParas(paras: string[], section: string | null, page: number | null, chunks: any[]) {
  let buf = "";
  const flush = () => { const t = buf.trim(); if (t) chunks.push({ section, page, content: t }); buf = ""; };
  for (let p of paras) {
    p = p.replace(/[ \t]+/g, " ").trim();
    if (!p) continue;
    while (p.length > MAXC) { if (buf) flush(); chunks.push({ section, page, content: p.slice(0, MAXC) }); p = p.slice(MAXC); }
    if ((buf + "\n" + p).length > MAXC) flush();
    buf = buf ? buf + "\n" + p : p;
  }
  flush();
}

async function parsePdf(bytes: Uint8Array) {
  const pdf = await getDocumentProxy(bytes);
  const { text } = await extractText(pdf, { mergePages: false });
  const pages: string[] = Array.isArray(text) ? text : [String(text || "")];
  const chunks: any[] = [];
  pages.forEach((pt, i) => {
    const paras = String(pt || "").split(/\n\s*\n/);
    packParas(paras.length > 1 ? paras : String(pt || "").split(/\n/), "Seite " + (i + 1), i + 1, chunks);
  });
  return { kind: "pdf", chunks, columns: [] };
}

function parseDocx(bytes: Uint8Array) {
  const files = unzipSync(bytes);
  const xmlU8 = files["word/document.xml"];
  if (!xmlU8) throw new Error("Kein Word-Dokument (word/document.xml fehlt)");
  const xml = strFromU8(xmlU8);
  // Jeder <w:p> ist ein Absatz; der sichtbare Text steht in den <w:t>-Runs darin.
  const paras: string[] = [];
  const pRe = /<w:p\b[^>]*>([\s\S]*?)<\/w:p>/g; let m: RegExpExecArray | null;
  while ((m = pRe.exec(xml)) !== null) {
    const inner = m[1];
    const tRe = /<w:t\b[^>]*>([\s\S]*?)<\/w:t>/g; let t: RegExpExecArray | null; let s = "";
    while ((t = tRe.exec(inner)) !== null) s += t[1];
    s = s.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&apos;/g, "'");
    if (s.trim()) paras.push(s);
  }
  const chunks: any[] = [];
  packParas(paras, null, null, chunks);
  return { kind: "docx", chunks, columns: [] };
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
  const b64 = String(body?.b64 || "");
  const name = String(body?.filename || "");
  if (!b64) return json({ error: "Keine Datei übergeben." }, 400);
  if (b64.length > 15_000_000) return json({ error: "Datei zu groß zum Auslesen (max. ~10 MB für PDF/Word)." }, 413);
  const ext = (name.split(".").pop() || "").toLowerCase();

  try {
    const bytes = b64ToBytes(b64);
    let res;
    if (ext === "pdf") res = await parsePdf(bytes);
    else if (ext === "docx") res = parseDocx(bytes);
    else return json({ error: "Format nicht unterstützt (nur PDF und Word .docx)." }, 415);
    if (!res.chunks.length) return json({ error: "Kein Text erkannt. Ist das PDF evtl. ein Scan (nur Bild)?" }, 422);
    return json({ ok: true, ...res });
  } catch (e) {
    return json({ error: "Datei nicht lesbar: " + ((e as Error).message || String(e)) }, 422);
  }
});
