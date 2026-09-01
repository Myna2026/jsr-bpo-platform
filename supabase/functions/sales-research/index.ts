// Sales-Akquise: Recherche + Aufhänger (manuell). Auth + Freigabeliste, dann geteilter Kern researchLead
// (Website holen, Claude leitet EINEN Aufhänger ab, keine erfundenen Fakten). Nur Freigabeliste.
// Deploy: supabase functions deploy sales-research --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { researchLead } from "../_shared/sales_core.ts";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC = Deno.env.get("ANTHROPIC_API_KEY") || "";
function json(b: unknown, s = 200) { return new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } }); }

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false, error: "POST" }, 405);
  const sb = createClient(SB_URL, SERVICE);
  const { data: u } = await sb.auth.getUser((req.headers.get("Authorization") || "").replace("Bearer ", ""));
  if (!u?.user) return json({ ok: false, error: "nicht angemeldet" }, 401);
  const { data: acc } = await sb.from("sales_access").select("user_id").eq("user_id", u.user.id).maybeSingle();
  if (!acc) return json({ ok: false, error: "kein Zugriff" }, 403);

  const leadId = (await req.json().catch(() => ({}))).lead_id;
  const { data: lead } = await sb.from("sales_leads").select("id,company,website,industry").eq("id", leadId).maybeSingle();
  if (!lead) return json({ ok: false, error: "Lead nicht gefunden" }, 404);

  const r = await researchLead(sb, lead, ANTHROPIC, u.user.id);
  return json(r.ok ? { ok: true, hook: r.hook } : { ok: false, error: r.error }, r.ok ? 200 : 502);
});
