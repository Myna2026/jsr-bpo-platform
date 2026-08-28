// Max gibt Teamleitern Anstöße — was sie TUN sollten, gegründet auf der echten Lage der Skill-Gruppe.
// HARTE REGEL: belegbare Namen/Einstufung NUR aus den Wochen-KPIs (weak/strong = Threshold-Band), nie geraten.
// Gibt die Lage keinen datengestützten Anstoß her, greift ein allgemeiner (behauptet nichts Falsches).
// Wechselnd (nie derselbe wie zuletzt), 2–3×/Woche (Mo–Fr, ≥2 Tage Abstand je Leiter). Mail (max@) + Slack.
// Team = (Projekt, Skill); Leiter = Position 'Teamleiter'. Cron: Mo–Fr. Deploy: functions deploy leader-nudges --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { agentBrand, shell, lead, button, PORTAL_URL } from "../_shared/agent_mail.ts";
import { smtpSend, slackDM, agentMailSender } from "../_shared/agent_send.ts";
import { isWeekendBerlin } from "../_shared/schedule.ts";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const CADENCE_MS = 2 * 864e5;
const NUM = ["null", "eine", "zwei", "drei", "vier", "fünf", "sechs", "sieben"];
const numW = (n: number) => n < NUM.length ? NUM[n] : String(n);
const uniq = (a: string[]) => [...new Set(a)];
const joinUnd = (a: string[]) => a.length <= 1 ? (a[0] || "") : a.slice(0, -1).join(", ") + " und " + a[a.length - 1];

function absentReason(absent: any[]) {
  // je Person GENAU EIN Typ (erster Eintrag), damit niemand doppelt zählt.
  const firstType: Record<string, string> = {};
  (absent || []).forEach((x) => { if (!firstType[x.name]) firstType[x.name] = x.type || "abwesend"; });
  const byType: Record<string, number> = {};
  Object.values(firstType).forEach((t) => { byType[t] = (byType[t] || 0) + 1; });
  const lbl: Record<string, string> = { sick: "krank", vacation: "im Urlaub", unpaid: "unbezahlt frei" };
  return Object.entries(byType).map(([t, n]) => numW(n) + " " + (lbl[t] || "abwesend")).join(" und ");
}

function fill(tpl: string, s: any) {
  const weakAll = uniq((s.weak || []).map((x: any) => x.name));
  const strongNames = uniq((s.strong || []).map((x: any) => x.name));
  // weak NACH KPI gruppieren; die dominante KPI (meiste Betroffene) trägt {weak_kpi_names}/{weak_kpi},
  // damit die Aussage belegbar konsistent ist (nicht Namen über verschiedene KPIs mischen).
  const byKpi: Record<string, string[]> = {};
  (s.weak || []).forEach((x: any) => { (byKpi[x.kpi] = byKpi[x.kpi] || []); if (!byKpi[x.kpi].includes(x.name)) byKpi[x.kpi].push(x.name); });
  const domKpi = Object.entries(byKpi).sort((a, b) => b[1].length - a[1].length)[0];
  const weakKpi = domKpi ? domKpi[0] : "den Kennzahlen";
  const weakKpiNames = domKpi ? domKpi[1] : [];
  const absentNames = uniq((s.absent || []).map((x: any) => x.name));
  const size = s.team_size || 0;
  const present = Math.max(0, size - absentNames.length);
  const nofb = s.no_feedback || [];
  const nofbNames = nofb.length <= 3 ? joinUnd(nofb) : joinUnd(nofb.slice(0, 2)) + " und " + numW(nofb.length - 2) + " weitere";
  const newNames = joinUnd(s.new_joiners || []);
  return tpl
    .replace(/\{weak_names\}/g, joinUnd(weakAll.slice(0, 2)))
    .replace(/\{weak_kpi_names\}/g, joinUnd(weakKpiNames.slice(0, 3)))
    .replace(/\{strong_names\}/g, joinUnd(strongNames.slice(0, 2)))
    .replace(/\{weak_kpi\}/g, weakKpi)
    .replace(/\{size\}/g, String(size))
    .replace(/\{present\}/g, numW(present))
    .replace(/\{absent_reason\}/g, absentReason(s.absent))
    .replace(/\{nofb_names\}/g, nofbNames)
    .replace(/\{new_names\}/g, newNames);
}

// Hält die Bedingung eines Anstoßes für diese Lage? (belegbar)
function condHolds(cond: string, s: any): boolean {
  const weakN = uniq((s.weak || []).map((x: any) => x.name)).length;
  const strongN = uniq((s.strong || []).map((x: any) => x.name)).length;
  const absentN = uniq((s.absent || []).map((x: any) => x.name)).length;
  switch (cond) {
    case "": return true;
    case "weak_strong": return weakN >= 2 && strongN >= 2;
    case "weak": return weakN >= 1;
    case "absent_stable": return absentN >= 1 && weakN === 0;   // abwesend, aber KPIs ok
    case "no_feedback": return (s.no_feedback || []).length >= 1;
    case "new_joiner": return (s.new_joiners || []).length >= 1;
    default: return false;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* Cron */ }
  const previewTo = (typeof body.preview_to === "string" && body.preview_to.includes("@")) ? body.preview_to : null;
  const force = body.force === true || !!previewTo, dry = body.dry === true;
  if (isWeekendBerlin() && !force) return json({ ok: true, skipped: "weekend" });

  const { data: sits, error } = await sb.rpc("leader_situations");
  if (error) return json({ error: "Situationen: " + error.message }, 502);
  const { data: cat } = await sb.from("leader_nudge_prompts").select("key,cond,template,prio").eq("active", true);
  const prompts = (cat || []).slice().sort((a: any, b: any) => b.prio - a.prio);

  // letzte Anstöße je Leiter (Kadenz + Rotation)
  const { data: acts } = await sb.from("agent_actions").select("at,meta").eq("agent_key", "max").eq("kind", "leader_nudge").order("at", { ascending: false }).limit(500);
  const lastAt: Record<string, string> = {}, lastKey: Record<string, string> = {};
  (acts || []).forEach((a: any) => { const u = a.meta && a.meta.user_id; if (u && !lastAt[u]) { lastAt[u] = a.at; lastKey[u] = (a.meta && a.meta.key) || ""; } });

  let emailBy: Record<string, string> = {}; try { const { data: al } = await sb.auth.admin.listUsers({ perPage: 200 }); (al?.users || []).forEach((u: any) => { if (u.email) emailBy[u.id] = u.email; }); } catch (_e) {}
  const brand = await agentBrand(sb, "max", "#2563eb");
  const sender = await agentMailSender(sb, "max");
  const results: any[] = [];
  const sentPreview = new Set<string>();   // Vorschau: je Gruppe+Anstoß nur einmal (keine Co-Leiter-Dubletten)

  for (const g of (sits || [])) {
    const s = g.situation || {};
    const scope = g.project_name + " · " + g.skill;
    const eligible = prompts.filter((p: any) => condHolds(p.cond, s));
    for (const L of (g.leaders || [])) {
      const uid = L.user_id; if (!uid) continue;
      // Kadenz
      if (!force && lastAt[uid] && (Date.now() - new Date(lastAt[uid]).getTime()) < CADENCE_MS) { results.push({ leader: L.name, skipped: "cadence" }); continue; }
      // Rotation: nicht denselben wie zuletzt
      const pool = eligible.filter((p: any) => p.key !== lastKey[uid]);
      const dataBacked = pool.filter((p: any) => p.cond !== "");
      const generals = pool.filter((p: any) => p.cond === "");
      let pick: any = null;
      if (dataBacked.length) pick = dataBacked[0];   // höchste prio zuerst
      else if (generals.length) { const idx = (new Date().getUTCDate() + L.name.length) % generals.length; pick = generals[idx]; }
      if (!pick) { results.push({ leader: L.name, skipped: "kein Anstoß" }); continue; }

      const text = fill(pick.template, s);
      const email = previewTo || emailBy[uid];
      if (dry) { results.push({ leader: L.name, scope, key: pick.key, text, email }); continue; }
      if (previewTo) { const dk = scope + "|" + pick.key; if (sentPreview.has(dk)) { results.push({ leader: L.name, skipped: "preview-dup" }); continue; } sentPreview.add(dk); }
      const html = shell(brand, "Ein Anstoß für dein Team", scope, lead(text) + button(PORTAL_URL, "Zum Team →", brand.accent));
      const subj = previewTo ? ("[Vorschau] Anstoß · " + L.name + " (" + scope + ")") : "Ein Anstoß für dein Team";
      const mr = (sender && email) ? await smtpSend(sender, email, subj, html) : { ok: false, error: "kein Empfänger" };
      const sr = previewTo ? "skip-preview" : await slackDM(email, "*Max · Anstoß*\n" + text);
      if (!previewTo) { try { await sb.from("agent_actions").insert({ agent_key: "max", kind: "leader_nudge", meta: { user_id: uid, key: pick.key, group: scope } }); } catch (_e) {}
        lastAt[uid] = new Date().toISOString(); lastKey[uid] = pick.key; }
      results.push({ leader: L.name, scope, key: pick.key, preview: !!previewTo, mail: mr.ok ? "sent" : mr.error, slack: sr });
    }
  }
  return json({ ok: true, groups: (sits || []).length, results });
});
