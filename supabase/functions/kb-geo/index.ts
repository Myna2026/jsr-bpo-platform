// Edge Function: Geografische Zuordnung bauen. Liest die echten Zielgebiete eines Partners und lässt Claude sie
// in geografische Container gruppieren (Insel/Region/Land), die ein Kunde am Telefon nennt — Kreta umfasst
// Heraklion & Chania, Balearen umfassen Mallorca & Ibiza, Türkische Riviera umfasst Antalya. Ergebnis wird
// DETERMINISTISCH in kb_regions gespeichert; die Suche (kb_retrieve) nutzt die feste Zuordnung, nicht die KI zur
// Suchzeit. Idempotent: ersetzt nur die KI-erzeugten Regionen (source='ki'), von Hand korrigierte (source='manuell')
// bleiben unangetastet. Zugriff/RLS über den Nutzer-Client (Area 'wissen' edit + Partner erlaubt).
// Deploy: supabase functions deploy kb-geo --use-api --no-verify-jwt
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

const GEO_TOOL = {
  name: "zuordnung",
  description: "Die geografische Gruppierung der Zielgebiete. Nur echte Geografie, members ausschließlich aus der vorgegebenen Liste.",
  input_schema: {
    type: "object",
    properties: {
      regions: {
        type: "array",
        description: "geografische Container (Inseln, Regionen, Gebiete, Länder), die ein Kunde am Telefon nennt",
        items: {
          type: "object",
          properties: {
            name: { type: "string", description: "geläufiger deutscher Name des Containers, z. B. 'Kreta', 'Balearen', 'Türkische Riviera'" },
            kind: { type: "string", enum: ["insel", "region", "land", "gebiet"], description: "Art des Containers" },
            aliases: { type: "array", items: { type: "string" }, description: "andere gängige Schreibweisen/Sprachen, z. B. ['Crete'] für Kreta. Ohne den reinen Ortsnamen." },
            members: { type: "array", items: { type: "string" }, description: "NUR Zielgebiete WÖRTLICH aus der vorgegebenen Liste, die geografisch dazugehören" },
          },
          required: ["name", "kind", "members"],
        },
      },
    },
    required: ["regions"],
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
  const uid = udata.user.id;

  let body: any = {}; try { body = await req.json(); } catch { /* egal */ }
  const projectId = String(body?.project_id || "").trim();
  if (!projectId) return json({ error: "Kein Partner angegeben." }, 400);
  if (!ANTHROPIC_KEY) return json({ error: "Der KI-Schlüssel ist noch nicht hinterlegt." }, 503);

  // Echte Zielgebiete (RLS gilt: kein Zugriff -> leer). Auch Rechte-Gate: ohne 'wissen' sieht der Nutzer 0 Zeilen.
  const { data: rows, error: qe } = await sb.from("kb_facts").select("zielgebiet")
    .eq("project_id", projectId).eq("status", "active").not("zielgebiet", "is", null);
  if (qe) return json({ error: "Zielgebiete konnten nicht geladen werden: " + qe.message }, 502);
  const zgSet = Array.from(new Set((rows || []).map((r: any) => String(r.zielgebiet || "").trim()).filter(Boolean)));
  if (!zgSet.length) return json({ ok: true, regions: 0, note: "Keine Zielgebiete hinterlegt." });

  const system =
    "Du ordnest die Zielgebiete eines Reiseveranstalters geografisch. Ziel: Wenn ein Kunde am Telefon eine Insel, " +
    "Region oder ein Gebiet nennt (z. B. \"Problem auf Kreta\"), soll das System die zugehörigen Orte finden.\n\n" +
    "REGELN:\n" +
    "- Gruppiere die vorgegebenen Zielgebiete unter geografischen Containern, die ein Kunde tatsächlich sagt: " +
    "Inseln (Kreta, Mallorca, Gran Canaria), Regionen/Gebiete (Türkische Riviera, Dodekanes, Balearen, Kanaren), " +
    "bei Bedarf Länder.\n" +
    "- 'members' sind AUSSCHLIESSLICH Zielgebiete WÖRTLICH aus der vorgegebenen Liste (kopiere den String exakt). " +
    "Erfinde keine Orte, rate nicht.\n" +
    "- Nutze nur echtes geografisches Wissen (welcher Ort liegt auf welcher Insel / in welcher Region / welchem Land).\n" +
    "- Ein Zielgebiet darf in mehreren Containern liegen (Heraklion ist auf Kreta UND in Griechenland). Lege primär die " +
    "nützlichen an (die Insel/Region, die der Kunde nennt); eine Länderebene nur, wenn sie zusätzlich hilft.\n" +
    "- 'aliases' = andere gängige Schreibweisen/Sprachen des Container-Namens (z. B. 'Crete' für Kreta, 'Balearic Islands' für Balearen).\n" +
    "- Container, für die es in der Liste keine passenden members gibt, lässt du weg.\n\n" +
    "ZIELGEBIETE:\n" + zgSet.map((z) => "- " + z).join("\n");

  let tool: any;
  try {
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": ANTHROPIC_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: MODEL, max_tokens: 3000, system, tools: [GEO_TOOL], tool_choice: { type: "tool", name: "zuordnung" }, messages: [{ role: "user", content: "Ordne die Zielgebiete geografisch zu." }] }),
    });
    const data = await resp.json();
    if (!resp.ok) return json({ error: "KI-Fehler: " + (data?.error?.message || resp.status) }, 502);
    tool = (data.content || []).find((c: any) => c.type === "tool_use");
    if (!tool) return json({ error: "Keine verwertbare Antwort." }, 502);
  } catch (e) {
    return json({ error: "Die KI ist gerade nicht erreichbar: " + (e as Error).message }, 502);
  }

  let regionsRaw = (tool.input && tool.input.regions) || [];
  if (typeof regionsRaw === "string") { try { regionsRaw = JSON.parse(regionsRaw); } catch { regionsRaw = []; } }
  const zgLower = new Map(zgSet.map((z) => [z.toLowerCase(), z]));
  // Validieren: members nur aus der echten Liste (Halluzinationen raus); leere Container verwerfen.
  const clean = (Array.isArray(regionsRaw) ? regionsRaw : []).map((r: any) => {
    const members = Array.from(new Set(((r && Array.isArray(r.members)) ? r.members : [])
      .map((m: any) => zgLower.get(String(m || "").trim().toLowerCase()))
      .filter(Boolean)));
    const aliases = Array.from(new Set(((r && Array.isArray(r.aliases)) ? r.aliases : [])
      .map((a: any) => String(a || "").trim()).filter(Boolean)));
    return {
      name: String((r && r.name) || "").trim(),
      kind: ["insel", "region", "land", "gebiet"].includes(r && r.kind) ? r.kind : "gebiet",
      aliases, members,
    };
  }).filter((r: any) => r.name && r.members.length);

  // Idempotent: KI-erzeugte Regionen des Partners ersetzen, von Hand gepflegte behalten.
  const { error: de } = await sb.from("kb_regions").delete().eq("project_id", projectId).eq("source", "ki");
  if (de) return json({ error: "Konnte alte Zuordnung nicht ersetzen (Rechte?): " + de.message }, 403);
  if (clean.length) {
    const ins = clean.map((r: any) => ({ project_id: projectId, name: r.name, kind: r.kind, aliases: r.aliases, members: r.members, source: "ki", status: "active", created_by: uid, updated_by: uid }));
    const { error: ie } = await sb.from("kb_regions").insert(ins);
    if (ie) return json({ error: "Konnte Zuordnung nicht speichern: " + ie.message }, 502);
  }
  return json({ ok: true, regions: clean.length, mapped: clean.reduce((n: number, r: any) => n + r.members.length, 0),
    detail: clean.map((r: any) => ({ name: r.name, kind: r.kind, members: r.members.length })) });
});
