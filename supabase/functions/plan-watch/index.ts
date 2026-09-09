// Edge Function: KI-Aufsicht über den gemeinsamen Verbesserungsplan. Analysiert Fristen und Fortschritt eines
// Projekts, meldet sachlich, was liegenbleibt / wo es stockt, und gibt konkrete nächste Schritte. Nur aus den
// Daten, erfindet nichts. Zugriff über den Nutzer-Client (RLS: nur wer den Plan sehen darf). Meldung an UNS
// (Team), nicht an den Kunden. Deploy: supabase functions deploy plan-watch --use-api --no-verify-jwt
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const MODEL = "claude-sonnet-5";
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;

const TOOL = {
  name: "aufsicht",
  description: "Deine Aufsichts-Analyse des Plans. Nur aus den gegebenen Daten.",
  input_schema: {
    type: "object",
    properties: {
      summary: { type: "string", description: "2-3 Sätze zur Gesamtlage (Fortschritt, Tempo, Risiken)" },
      attention: { type: "array", description: "Punkte, die liegenbleiben oder stocken (überfällig, ohne Fortschritt, ohne Maßnahme). Leer, wenn alles im Fluss.", items: { type: "object", properties: { title: { type: "string" }, reason: { type: "string", description: "kurz, warum es Aufmerksamkeit braucht" } }, required: ["title", "reason"] } },
      recommendations: { type: "array", description: "1-3 konkrete nächste Schritte", items: { type: "string" } },
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
  if (!udata?.user?.id) return json({ error: "Sitzung ungültig." }, 401);

  let body: any = {}; try { body = await req.json(); } catch { /* egal */ }
  const projectId = String(body?.project_id || "").trim();
  if (!projectId) return json({ error: "Kein Projekt angegeben." }, 400);
  if (!ANTHROPIC_KEY) return json({ error: "Der KI-Schlüssel ist nicht hinterlegt." }, 503);

  const { data: rows, error } = await sb.from("improvement_items").select("*").eq("project_id", projectId).order("sort_order");
  if (error) return json({ error: "Plan konnte nicht geladen werden: " + error.message }, 502);
  const items: any[] = rows || [];
  if (!items.length) return json({ report: { summary: "Der Plan hat noch keine Punkte.", attention: [], recommendations: [] }, signals: { overdue: 0, noMeasure: 0, stalled: 0, total: 0 } });

  const today = new Date().toISOString().slice(0, 10);
  const active = (i: any) => i.status !== "erledigt" && i.status !== "zurueckgestellt";
  const overdue = items.filter((i) => i.due_date && String(i.due_date).slice(0, 10) < today && i.status !== "erledigt");
  const noMeasure = items.filter((i) => !i.parent_id && (!i.measures || !String(i.measures).trim()) && active(i));
  const stalled = items.filter((i) => (i.progress || 0) === 0 && active(i));
  const byId: any = {}; items.forEach((i) => (byId[i.id] = i));
  const plan = items.map((i) => {
    const parent = i.parent_id && byId[i.parent_id] ? byId[i.parent_id].title + " › " : "";
    return `- [${i.priority}] ${parent}${i.title} · Status ${i.status} · Fortschritt ${i.progress || 0}%` +
      (i.due_date ? " · Frist " + String(i.due_date).slice(0, 10) : " · keine Frist") +
      (i.measures && String(i.measures).trim() ? " · Maßnahme: " + i.measures : " · KEINE Maßnahme") +
      (i.origin === "client" ? " · von Condor genannt" : "");
  }).join("\n");

  const system =
    "Du bist die KI-Aufsicht über einen gemeinsamen Verbesserungsplan zwischen unserem Callcenter und dem Kunden. " +
    "Analysiere Fristen und Fortschritt, melde SACHLICH und knapp, was liegenbleibt und wo es stockt, und gib konkrete nächste Schritte. " +
    "Heute ist " + today + ". Nutze NUR die Daten unten, erfinde nichts. Die Meldung geht an unser Team, nicht an den Kunden.\n\n" +
    "PLAN:\n" + plan + "\n\n" +
    "SIGNALE (bereits ausgezählt): überfällig " + overdue.length + ", Hauptpunkte ohne Maßnahme " + noMeasure.length + ", ohne Fortschritt " + stalled.length + ".";

  try {
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": ANTHROPIC_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: MODEL, max_tokens: 1100, system, tools: [TOOL], tool_choice: { type: "tool", name: "aufsicht" }, messages: [{ role: "user", content: "Analysiere den Plan und melde, was Aufmerksamkeit braucht." }] }),
    });
    const data = await resp.json();
    if (!resp.ok) return json({ error: "KI-Fehler: " + (data?.error?.message || resp.status) }, 502);
    const tool = (data.content || []).find((c: any) => c.type === "tool_use");
    if (!tool) return json({ error: "Keine verwertbare Antwort." }, 502);
    const out = tool.input || {};
    const report = {
      summary: String(out.summary || "").trim(),
      attention: Array.isArray(out.attention) ? out.attention.filter((a: any) => a && a.title).map((a: any) => ({ title: String(a.title).trim(), reason: String(a.reason || "").trim() })) : [],
      recommendations: Array.isArray(out.recommendations) ? out.recommendations.filter((r: any) => r && String(r).trim()).map((r: any) => String(r).trim()) : [],
    };
    return json({ report, signals: { overdue: overdue.length, noMeasure: noMeasure.length, stalled: stalled.length, total: items.length } });
  } catch (e) {
    return json({ error: "Die KI ist gerade nicht erreichbar: " + (e as Error).message }, 502);
  }
});
