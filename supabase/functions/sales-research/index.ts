// Sales-Akquise, Schnitt 2: Recherche + Aufhänger. Holt die Firmen-Website, Claude fasst zusammen (Branche, was die
// Firma macht, wo unser Angebot passt) und formuliert EINEN konkreten Aufhänger. HARTE REGEL: nur Fakten aus dem
// Text; gibt er nichts her → allgemein bleiben, NICHTS über die Firma erfinden. Nur Freigabeliste.
// Deploy: supabase functions deploy sales-research --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC = Deno.env.get("ANTHROPIC_API_KEY") || "";
function json(b: unknown, s = 200) { return new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } }); }

async function fetchSiteText(website: string): Promise<string> {
  let url = website.trim(); if (!/^https?:\/\//i.test(url)) url = "https://" + url;
  try {
    const r = await fetch(url, { headers: { "User-Agent": "Mozilla/5.0 (compatible; 25HRS-Research/1.0)" }, signal: AbortSignal.timeout(9000) });
    if (!r.ok) return "";
    let html = await r.text();
    html = html.replace(/<script[\s\S]*?<\/script>/gi, " ").replace(/<style[\s\S]*?<\/style>/gi, " ").replace(/<!--[\s\S]*?-->/g, " ");
    const text = html.replace(/<[^>]+>/g, " ").replace(/&[a-z]+;/gi, " ").replace(/\s+/g, " ").trim();
    return text.slice(0, 9000);
  } catch (_e) { return ""; }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false, error: "POST" }, 405);
  const sb = createClient(SB_URL, SERVICE);
  const { data: u } = await sb.auth.getUser((req.headers.get("Authorization") || "").replace("Bearer ", ""));
  if (!u?.user) return json({ ok: false, error: "nicht angemeldet" }, 401);
  const { data: acc } = await sb.from("sales_access").select("user_id").eq("user_id", u.user.id).maybeSingle();
  if (!acc) return json({ ok: false, error: "kein Zugriff" }, 403);
  if (!ANTHROPIC) return json({ ok: false, error: "ANTHROPIC_API_KEY fehlt" }, 400);

  const leadId = (await req.json().catch(() => ({}))).lead_id;
  const { data: lead } = await sb.from("sales_leads").select("id,company,website,industry").eq("id", leadId).maybeSingle();
  if (!lead) return json({ ok: false, error: "Lead nicht gefunden" }, 404);

  const siteText = lead.website ? await fetchSiteText(lead.website) : "";
  const thin = siteText.length < 200;

  const sys = "Du recherchierst für einen Vertriebs-Erstkontakt. Unser Angebot: Customer Journey mit Offshore-Standorten " +
    "im deutschsprachigen Raum (Kundenservice/Support über unsere Standorte in Kosovo und Albanien). Aus dem Website-Text " +
    "einer Firma leitest du ab: was die Firma macht, ihre Branche, und wo unser Angebot konkret passt. Formuliere EINEN " +
    "kurzen, konkreten Aufhänger (1-2 Sätze), der zeigt, dass wir uns mit der Firma beschäftigt haben — kein Einheitsbrei. " +
    "HARTE REGEL: Nur Fakten, die im Text stehen. Gibt der Text nichts her, bleibt der Aufhänger allgemein und du setzt " +
    "hook_general=true; erfinde NIEMALS Firmen-Fakten. Antworte NUR als JSON: {summary, industry, fit, hook, hook_general}.";
  const usr = thin
    ? "Es liegt kein brauchbarer Website-Text vor (Firma: " + (lead.company || "unbekannt") + "). Bleib allgemein, hook_general=true, keine erfundenen Fakten."
    : "Firma: " + (lead.company || "?") + "\n\nWebsite-Text:\n" + siteText;

  let obj: any = {};
  try {
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST", headers: { "x-api-key": ANTHROPIC, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: "claude-sonnet-5", max_tokens: 600, system: sys, messages: [{ role: "user", content: usr }] }),
    });
    if (!r.ok) return json({ ok: false, error: "Claude " + r.status + ": " + (await r.text()).slice(0, 160) }, 502);
    const raw = ((await r.json()).content || []).map((c: any) => c.text || "").join("");
    const m = raw.match(/\{[\s\S]*\}/); obj = m ? JSON.parse(m[0]) : {};
  } catch (e) { return json({ ok: false, error: "Recherche fehlgeschlagen: " + ((e as Error).message || e) }, 502); }

  const research = { summary: obj.summary || null, industry: obj.industry || null, fit: obj.fit || null,
    hook_general: !!obj.hook_general, fetched: !thin, chars: siteText.length, at: new Date().toISOString() };
  const upd: Record<string, unknown> = { research, hook: obj.hook || null, status: "researched", last_activity_at: new Date().toISOString() };
  if (obj.industry && !lead.industry) upd.industry = obj.industry;
  await sb.from("sales_leads").update(upd).eq("id", lead.id);
  await sb.from("sales_events").insert({ lead_id: lead.id, kind: "research", actor: u.user.id, detail: { fetched: !thin, hook_general: research.hook_general } });
  return json({ ok: true, hook: obj.hook || null, research });
});
