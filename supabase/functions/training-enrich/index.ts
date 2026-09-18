// Miriams Ebenen (Warum · Einwand · Anwendung) in die Fragenbank schreiben: alle aktiven, geprüften Fragen (quality ≥ 4)
// ohne layers, je Aufruf eine Portion (limit, Standard 40). Nachts per Cron nach coach-generate; manuell {"project_id","limit","sync":true}.
// Deploy: supabase functions deploy training-enrich --use-api --no-verify-jwt
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { buildLayers } from "../_shared/training_layers.ts";
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };
async function portion(pid: string, limit: number) {
  const { data: rows } = await admin.from("coach_questions").select("*").eq("project_id", pid).eq("status", "active").gte("quality", 4).is("layers", null).limit(limit);
  const list = rows || []; if (!list.length) return { project_id: pid, done: 0, remaining: 0 };
  const built = await buildLayers(admin, pid, list); let done = 0; const now = new Date().toISOString();
  for (const x of list) { const l = built[x.id] || { why: null, objection: null, apply: null, empty: true }; const { error } = await admin.from("coach_questions").update({ layers: l, layers_at: now }).eq("id", x.id); if (!error) done++; }
  const { count } = await admin.from("coach_questions").select("id", { count: "exact", head: true }).eq("project_id", pid).eq("status", "active").gte("quality", 4).is("layers", null);
  return { project_id: pid, done, remaining: count || 0 };
}
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* Cron */ }
  const limit = Math.max(4, Math.min(80, Number(body.limit) || 40));
  const projects: string[] = body.project_id ? [String(body.project_id)] : [...new Set(((await admin.from("coach_questions").select("project_id").eq("status", "active").is("layers", null).limit(2000)).data || []).map((r: any) => r.project_id))];
  if (body.sync === true) { const out = []; for (const pid of projects) out.push(await portion(pid, limit)); return json({ ok: true, report: out }); }
  EdgeRuntime.waitUntil((async () => { for (const pid of projects) { try { console.log("[training-enrich]", JSON.stringify(await portion(pid, limit))); } catch (e) { console.error("[training-enrich]", (e as Error).message); } } })());
  return json({ ok: true, started: true, projects, limit });
});
