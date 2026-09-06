// Edge Function: kb-catalog (Wissensspeicher Schnitt 5). Liest die Abschnitte eines eingespeisten Dokuments und
// lässt Claude die einzelnen, nachschlagbaren FAKTEN vorschlagen (Notfallnummern, Transferzeiten, Kontakte,
// Regeln, Preise, Abläufe) — mit Thema, Zielgebiet, Unterscheidung und Fundstelle. Es SCHREIBT nichts: es
// schlägt nur vor. Der Mensch entscheidet in der UI, was ins Register übernommen wird ("Ich entscheide, das
// System schlägt vor"). Erfindet nichts — nur was im Text steht.
// Deploy: supabase functions deploy kb-catalog --use-api --no-verify-jwt
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

const TOOL = {
  name: "vorschlaege",
  description: "Die aus dem Dokument extrahierten Einzelfakten fürs Register. Nur was wirklich dasteht.",
  input_schema: {
    type: "object",
    properties: {
      facts: {
        type: "array",
        description: "einzelne nachschlagbare Fakten; leere Liste, wenn nichts Strukturierbares drinsteht",
        items: {
          type: "object",
          properties: {
            topic: { type: "string", description: "Oberbegriff/Thema, z. B. Notfallnummer, Transfer, Check-in, Gepäck" },
            zielgebiet: { type: ["string", "null"], description: "Ort/Region, falls genannt (z. B. Rhodos), sonst null" },
            info_type: { type: "string", enum: ["kontakt", "zeit", "ablauf", "regel", "preis", "sonstiges"] },
            label: { type: "string", description: "kurzer Titel des Eintrags" },
            value: { type: "string", description: "die konkrete Angabe, möglichst wörtlich aus dem Text" },
            saison: { type: ["string", "null"], description: "nur wenn der Wert je Saison unterschiedlich ist, sonst null" },
            veranstalter: { type: ["string", "null"], description: "nur wenn der Wert je Veranstalter unterschiedlich ist, sonst null" },
            source_locator: { type: ["string", "null"], description: "Fundstelle wörtlich aus den eckigen Klammern (z. B. Seite 3), sonst null" },
          },
          required: ["topic", "label", "value"],
        },
      },
    },
    required: ["facts"],
  },
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST erwartet" }, 405);
  const auth = req.headers.get("Authorization") || "";
  if (!auth) return json({ error: "Nicht angemeldet." }, 401);
  const sb = createClient(SB_URL, ANON, { global: { headers: { Authorization: auth } } });
  const { data: udata } = await sb.auth.getUser();
  if (!udata?.user?.id) return json({ error: "Sitzung ungültig." }, 401);
  if (!ANTHROPIC_KEY) return json({ error: "Der KI-Schlüssel ist noch nicht hinterlegt." }, 503);

  let body: any = {}; try { body = await req.json(); } catch { /* egal */ }
  const documentId = String(body?.document_id || "").trim();
  if (!documentId) return json({ error: "Kein Dokument angegeben." }, 400);

  // Abschnitte über den User-Client lesen -> RLS/Perm entscheidet über Zugriff (kein Leak über Partnergrenzen).
  const { data: chunks, error: ce } = await sb.from("kb_chunks").select("section,page,content").eq("document_id", documentId).order("ord");
  if (ce) return json({ error: "Abschnitte nicht lesbar: " + ce.message }, 502);
  if (!chunks || !chunks.length) return json({ ok: true, facts: [], note: "Keine Abschnitte gefunden." });

  const system =
    "Du katalogisierst Wissen für ein Kundenprojekt. Aus dem folgenden Dokument-Text ziehst du die einzelnen, " +
    "nachschlagbaren FAKTEN heraus — so, dass man sie später gezielt abfragen kann.\n\n" +
    "REGELN:\n" +
    "- Ein Fakt = eine klar beantwortbare Angabe (eine Notfallnummer, eine Transferzeit, ein Kontakt, eine Regel, ein Ablaufschritt).\n" +
    "- Enthält eine Zeile MEHRERE Angaben (z. B. je Zielgebiet: Treffpunkt UND Notfallnummer UND Rückweg), dann mach daraus MEHRERE Fakten, einen je Angabe.\n" +
    "- Erfinde NICHTS. Nimm nur, was wörtlich im Text steht. Der 'value' soll möglichst wörtlich sein.\n" +
    "- 'zielgebiet' nur, wenn ein Ort/Gebiet genannt ist. 'saison'/'veranstalter' nur, wenn der Text den Wert danach unterscheidet.\n" +
    "- 'source_locator' aus dem [..]-Marker der Zeile, aus der der Fakt stammt.\n" +
    "- Fasse NICHT zusammen und lasse Fließtext ohne konkrete Angabe weg. Steht nichts Strukturierbares drin: leere Liste.\n\n";

  // In kleinen Häppchen katalogisieren (~2200 Zeichen ≈ wenige Zielgebiete je Aufruf) und PARALLEL verarbeiten.
  // Grund: bei großen Häppchen extrahiert das Modell nicht erschöpfend / läuft in die max_tokens-Grenze und
  // liefert leer. Kleine Häppchen = vollständige Erfassung je Zeile; parallel = schnell trotz vieler Aufrufe.
  const BATCH_CHARS = 2200, MAX_BATCHES = 24;
  const batches: string[] = []; let cur = "";
  for (const c of chunks) {
    const marker = c.section ? c.section : (c.page ? "Seite " + c.page : "-");
    const line = "[" + marker + "] " + String(c.content || "") + "\n";
    if (cur && cur.length + line.length > BATCH_CHARS) { batches.push(cur); cur = ""; }
    cur += line;
  }
  if (cur) batches.push(cur);
  const truncated = batches.length > MAX_BATCHES;
  const use = batches.slice(0, MAX_BATCHES);

  async function catalogBatch(txt: string): Promise<any[]> {
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": ANTHROPIC_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: MODEL, max_tokens: 4000, system: system + "DOKUMENT-TEXT:\n" + txt, tools: [TOOL], tool_choice: { type: "tool", name: "vorschlaege" }, messages: [{ role: "user", content: "Katalogisiere die Fakten." }] }),
    });
    const data = await resp.json();
    if (!resp.ok) throw new Error(data?.error?.message || ("HTTP " + resp.status));
    const tool = (data.content || []).find((c: any) => c.type === "tool_use");
    return (tool && Array.isArray(tool.input?.facts)) ? tool.input.facts : [];
  }

  const results = await Promise.all(use.map((t) => catalogBatch(t).then((f) => ({ f })).catch((e) => ({ e: (e as Error).message || String(e) }))));
  let raw: any[] = []; let lastErr = "";
  for (const r of results) { if ((r as any).f) raw = raw.concat((r as any).f); else if ((r as any).e) lastErr = (r as any).e; }
  if (!raw.length && lastErr) return json({ error: "KI-Fehler: " + lastErr }, 502);

  const facts = raw.filter((f) => f && f.topic && f.label && f.value).map((f) => ({
    topic: String(f.topic).trim(),
    zielgebiet: (f.zielgebiet && String(f.zielgebiet).trim()) || null,
    info_type: ["kontakt", "zeit", "ablauf", "regel", "preis", "sonstiges"].includes(f.info_type) ? f.info_type : "sonstiges",
    label: String(f.label).trim(),
    value: String(f.value).trim(),
    saison: (f.saison && String(f.saison).trim()) || null,
    veranstalter: (f.veranstalter && String(f.veranstalter).trim()) || null,
    source_locator: (f.source_locator && String(f.source_locator).trim()) || null,
  }));
  return json({ ok: true, facts, truncated });
});
