// Sales-Akquise, Schnitt F: Moritz betreibt die Akquise selbst. Orchestrator, läuft per Cron (und auf Knopf).
// Ablauf: (1) Prioritäten neu rechnen, (2) offene Leads recherchieren (Aufhänger), (3) NUR wenn Autonomie an:
// die höchstpriorisierten researched-Leads zum Erstkontakt anschreiben (Tages-Deckel), (4) Tagesplan + Zusammenfassung
// ablegen. Compliance steckt im geteilten deliverStage. Antworten/Übergabe brauchen den Postfach-Eingang (Zoho OAuth)
// und sind hier bewusst NICHT enthalten (inbound_pending). Öffentlich (--no-verify-jwt), selbst-drosselnd über Deckel.
// Deploy: supabase functions deploy sales-agent-run --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { deliverStage, researchLead } from "../_shared/sales_core.ts";

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
  const autoContact = cfg.enabled === true && cfg.auto_first_contact !== false;
  const dailyCap = Number(cfg.daily_cap) || 15;

  // 1. Prioritäten neu rechnen.
  await sb.rpc("sales_recompute_scores");

  // 2. Recherche für neue Leads mit Website (Aufhänger), gedeckelt.
  let researched = 0;
  if (autoResearch) {
    const { data: toRes } = await sb.from("sales_leads").select("id,company,website,industry")
      .eq("status", "new").not("website", "is", null).order("created_at", { ascending: true }).limit(researchCap);
    for (const l of toRes || []) { const r = await researchLead(sb, l, ANTHROPIC, null); if (r.ok) researched++; }
  }

  // 3. Erstkontakt NUR bei aktiver Autonomie, Tages-Deckel über heute schon autonom Versandtes.
  let contacted = 0; const contactErrors: string[] = [];
  if (autoContact) {
    const startToday = new Date(); startToday.setUTCHours(0, 0, 0, 0);
    const { count: sentToday } = await sb.from("sales_events").select("id", { count: "exact", head: true })
      .eq("kind", "sent").eq("detail->>auto", "erstkontakt").gte("occurred_at", startToday.toISOString());
    let remaining = Math.max(0, dailyCap - (sentToday || 0));
    const { data: tpls } = await sb.from("sales_templates").select("*").eq("stage", "erstansprache").eq("active", true);
    if (remaining > 0 && tpls && tpls.length) {
      const { data: cands } = await sb.from("sales_leads").select("*")
        .eq("status", "researched").not("contact_email", "is", null).order("score", { ascending: false, nullsFirst: false }).limit(remaining);
      for (const l of cands || []) {
        if (remaining <= 0) break;
        const tpl = tpls[Number(l.id) % tpls.length];
        const r = await deliverStage(sb, l, tpl, null, { anthropic: ANTHROPIC, auto: "erstkontakt" });
        if (r.ok) { contacted++; remaining--; } else if (r.error) contactErrors.push((l.company || "?") + ": " + r.error);
      }
    }
  }

  // 4. Tagesplan (für den Menschen) + Zusammenfassung ablegen.
  const { data: top } = await sb.from("sales_leads").select("id,company,score,status")
    .in("status", ["researched", "contacted", "opened", "replied"]).order("score", { ascending: false, nullsFirst: false }).limit(6);
  const summary = {
    at: new Date().toISOString(), researched, contacted, autonomy: autoContact,
    plan: (top || []).map((t: any) => ({ company: t.company, score: t.score, status: t.status })),
    note: autoContact ? null : "Autonomer Erstkontakt ist aus. Moritz recherchiert und priorisiert, sendet aber nur auf deine Freigabe.",
    inbound_pending: true,   // Antworten/Übergabe erst mit Postfach-Eingang (Zoho OAuth)
  };
  await sb.from("app_config").upsert({ key: "jsr_sales_agent_last_v1", value: summary }, { onConflict: "key" });

  return json({ ok: true, researched, contacted, autonomy: autoContact, errors: contactErrors.slice(0, 5) });
});
