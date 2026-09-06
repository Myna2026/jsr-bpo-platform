// Edge Function: kb-mail (Wissensspeicher Schnitt 17). Formuliert aus den vom Bearbeiter AUSGEWÄHLTEN
// Antwort-Blöcken eine freundliche, sendbare Kunden-Mail (Anrede + Schluss, im Ton des Partners) — kein
// Aneinanderkleben. Grundregel: die KI gestaltet NUR den Ton/verbindenden Text; Nummern, Adressen und Abläufe
// bleiben WÖRTLICH und werden nicht erfunden. Gibt {subject, body} zurück; der Client öffnet daraus eine
// mailto:-Vorlage im Mailprogramm des Bearbeiters (er ergänzt Adresse, liest, sendet selbst — nichts geht
// automatisch raus). Deploy: supabase functions deploy kb-mail --use-api --no-verify-jwt
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

const MAIL_TOOL = {
  name: "mail",
  description: "Die fertige, sendbare Kunden-Mail aus den gegebenen Inhalten.",
  input_schema: {
    type: "object",
    properties: {
      subject: { type: "string", description: "kurze, passende Betreffzeile" },
      body: { type: "string", description: "die vollständige Mail: Anrede, Fließtext aus den Inhalten, freundlicher Schluss. Zeilenumbrüche mit \\n." },
    },
    required: ["subject", "body"],
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
  const projectId = String(body?.project_id || "").trim();
  const blocks: any[] = Array.isArray(body?.blocks) ? body.blocks.filter((b: any) => b && b.text) : [];
  const question = String(body?.question || "").trim();
  if (!projectId) return json({ error: "Kein Partner angegeben." }, 400);
  if (!blocks.length) return json({ error: "Keine Inhalte ausgewählt." }, 400);

  // Zugriff prüfen: darf der Aufrufer diesen Partner sehen? (gleiche Regel wie kb_retrieve)
  const { data: chk } = await sb.rpc("kb_retrieve", { p_project: projectId, p_q: "x", p_limit: 1 });
  if (chk && chk.ok === false) return json({ error: "Kein Zugriff auf diesen Partner." }, 403);

  const inhalte = blocks.map((b: any, i: number) => (i + 1) + ". " + (b.title ? b.title + ": " : "") + String(b.text).trim()).join("\n");

  const system =
    "Du schreibst für einen Call-Center-Bearbeiter eine kurze, freundliche und professionelle E-Mail an einen KUNDEN. " +
    "Aus den gegebenen INHALTEN machst du einen zusammenhängenden, gut lesbaren Text, den man so verschicken kann.\n\n" +
    "EISERNE REGELN:\n" +
    "- Sieze den Kunden. Beginne mit einer neutralen Anrede (\"Guten Tag,\") und ende mit \"Mit freundlichen Grüßen\" als LETZTER Zeile.\n" +
    "- Die Mail ist vom Reiseunternehmen an den Kunden. Nenne KEINEN Assistenten-, Kollegen- oder Vornamen, stelle dich NICHT namentlich vor und unterschreibe NICHT mit einem Namen. Der Bearbeiter fügt seine Signatur selbst unter dem Gruß ein.\n" +
    "- Nutze NUR die gegebenen Inhalte. Erfinde NICHTS dazu.\n" +
    "- Nummern, Adressen, Uhrzeiten, Schalter/Orte und Ablaufschritte übernimmst du WÖRTLICH und unverändert. Du darfst nur den verbindenden Text und den Ton gestalten, keine Angabe umformulieren oder weglassen.\n" +
    "- Kein stures Aneinanderkleben der Punkte, sondern ein natürlicher, höflicher Text.\n\n" +
    (question ? ("ANLASS (Kontext, nicht mitschicken): " + question + "\n\n") : "") +
    "INHALTE (wörtlich einzubauen):\n" + inhalte;

  let tool: any;
  try {
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": ANTHROPIC_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: MODEL, max_tokens: 1200, system, tools: [MAIL_TOOL], tool_choice: { type: "tool", name: "mail" }, messages: [{ role: "user", content: "Schreibe die Kunden-Mail." }] }),
    });
    const data = await resp.json();
    if (!resp.ok) return json({ error: "KI-Fehler: " + (data?.error?.message || resp.status) }, 502);
    tool = (data.content || []).find((c: any) => c.type === "tool_use");
    if (!tool) return json({ error: "Keine verwertbare Antwort." }, 502);
  } catch (e) {
    return json({ error: "Die KI ist gerade nicht erreichbar: " + (e as Error).message }, 502);
  }

  const out = tool.input || {};
  return json({ ok: true, subject: String(out.subject || "").trim(), body: String(out.body || "").trim() });
});
