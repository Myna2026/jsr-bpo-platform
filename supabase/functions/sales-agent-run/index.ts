// Sales-Akquise, Schnitt F: Moritz betreibt die Akquise selbst. Vorbereitungs-Lauf, per Cron (und auf Knopf).
// Ablauf: (1) Prioritäten neu rechnen, (2) offene Leads recherchieren (Aufhänger), (3) Tagesplan + Zusammenfassung.
// Der eigentliche VERSAND läuft NICHT hier, sondern verteilt über sales-dispatch (Versand-Rhythmus, kein Batch).
// Antworten/Übergabe brauchen den Postfach-Eingang (Zoho OAuth) und sind hier bewusst NICHT enthalten.
// Öffentlich (--no-verify-jwt). Deploy: supabase functions deploy sales-agent-run --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { researchLead } from "../_shared/sales_core.ts";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC = Deno.env.get("ANTHROPIC_API_KEY") || "";
function json(b: unknown, s = 200) { return new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } }); }

Deno.serve(async (_req) => {
  const sb = createClient(SB_URL, SERVICE);
  const { data: cfgRow } = await sb.from("app_config").select("value").eq("key", "jsr_sales_autonomy_v1").maybeSingle();
  const cfg: any = cfgRow?.value || {};
  const autoResearch = cfg.auto_research !== false;
  const researchCap = Number(cfg.research_cap) || 10;

  // 1. Prioritäten neu rechnen.
  await sb.rpc("sales_recompute_scores");

  // 2. Recherche für neue Leads mit Website (Aufhänger), gedeckelt.
  let researched = 0;
  if (autoResearch) {
    const { data: toRes } = await sb.from("sales_leads").select("id,company,website,industry")
      .eq("status", "new").not("website", "is", null).order("created_at", { ascending: true }).limit(researchCap);
    for (const l of toRes || []) { const r = await researchLead(sb, l, ANTHROPIC, null); if (r.ok) researched++; }
  }

  // 3. Tagesplan (für den Menschen) + Zusammenfassung. Versand macht der Rhythmus-Dispatcher.
  const startToday = new Date(); startToday.setUTCHours(0, 0, 0, 0);
  const { count: sentToday } = await sb.from("sales_events").select("id", { count: "exact", head: true })
    .eq("kind", "sent").is("actor", null).eq("detail->>ok", "true").gte("occurred_at", startToday.toISOString());
  const { data: top } = await sb.from("sales_leads").select("id,company,score,status")
    .in("status", ["researched", "contacted", "opened", "replied"]).order("score", { ascending: false, nullsFirst: false }).limit(6);
  const autoContact = cfg.enabled === true && cfg.auto_first_contact !== false;
  const summary = {
    at: new Date().toISOString(), researched, sent_today: sentToday || 0, autonomy: cfg.enabled === true,
    plan: (top || []).map((t: any) => ({ company: t.company, score: t.score, status: t.status })),
    note: cfg.enabled === true
      ? (autoContact ? "Versand läuft verteilt über den Tag (Rhythmus), nicht als Schwung." : "Nachfasser gehen verteilt raus, Erstkontakt nur auf deine Freigabe.")
      : "Autonomie ist aus. Moritz recherchiert und priorisiert, sendet aber nur auf deine Freigabe.",
    inbound_pending: true,   // Antworten/Übergabe erst mit Postfach-Eingang (Zoho OAuth)
  };
  await sb.from("app_config").upsert({ key: "jsr_sales_agent_last_v1", value: summary }, { onConflict: "key" });

  return json({ ok: true, researched, sent_today: sentToday || 0, autonomy: cfg.enabled === true });
});
