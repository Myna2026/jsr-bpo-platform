// Sales-Akquise: automatische Nachfass-Strecke. Läuft per Cron. Sucht fällige Leads (next_followup_at erreicht,
// noch keine Antwort) und sendet die NÄCHSTE Stufe (nicht dieselbe Mail) über den geteilten Kern deliverStage
// (Compliance identisch zum manuellen Versand). Verhaltensbasierter Rhythmus + Kettenende stecken in deliverStage.
// Öffentlich (--no-verify-jwt): sendet nur an echt fällige Leads, jeder Versand schiebt den Termin vor (selbst-drosselnd).
// Deploy: supabase functions deploy sales-followup --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { deliverStage } from "../_shared/sales_core.ts";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC = Deno.env.get("ANTHROPIC_API_KEY") || "";
const CHAIN_DEFAULT: Record<string, string | null> = { erstansprache: "nachfass1", nachfass1: "nachfass2", nachfass2: "letzter", letzter: null, reaktivierung: null };

function json(b: unknown, s = 200) { return new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } }); }

Deno.serve(async (_req) => {
  const sb = createClient(SB_URL, SERVICE);
  const { data: cfgRow } = await sb.from("app_config").select("value").eq("key", "jsr_sales_followup_v1").maybeSingle();
  const chain: Record<string, string | null> = { ...CHAIN_DEFAULT, ...((cfgRow?.value as any)?.chain || {}) };

  // Fällige Leads: angeschrieben/geöffnet, Frist erreicht, mit E-Mail. Antworten (status replied/handover) sind raus.
  const nowIso = new Date().toISOString();
  const { data: due } = await sb.from("sales_leads").select("*")
    .in("status", ["contacted", "opened"]).lte("next_followup_at", nowIso).not("contact_email", "is", null)
    .order("next_followup_at", { ascending: true }).limit(200);

  let sent = 0, ended = 0, skipped = 0; const errors: string[] = [];
  for (const lead of due || []) {
    const nextStage = chain[lead.stage || "erstansprache"];
    if (!nextStage) {  // Kette zu Ende (nach 'letzter'): keine weitere Mail, Termin räumen, Tot-Erkennung übernimmt.
      await sb.from("sales_leads").update({ next_followup_at: null }).eq("id", lead.id); ended++; continue;
    }
    const { data: tpls } = await sb.from("sales_templates").select("*").eq("stage", nextStage).eq("active", true);
    if (!tpls || !tpls.length) {  // keine Vorlage für die nächste Stufe → Termin kurz vertagen, nicht endlos triggern.
      await sb.from("sales_leads").update({ next_followup_at: new Date(Date.now() + 3 * 864e5).toISOString() }).eq("id", lead.id); skipped++; continue;
    }
    const tpl = tpls[Number(lead.id) % tpls.length];   // Varianten je Stufe rotieren (nicht alle bekommen dasselbe)
    const r = await deliverStage(sb, lead, tpl, null, { anthropic: ANTHROPIC, auto: "nachgefasst" });
    if (r.ok) sent++; else { skipped++; if (r.error) errors.push(lead.company + ": " + r.error); }
  }
  return json({ ok: true, due: (due || []).length, sent, ended, skipped, errors: errors.slice(0, 5) });
});
