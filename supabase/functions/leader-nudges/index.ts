// Max gibt Teamleitern Anstöße — was sie TUN sollten, gegründet auf der echten Lage der Skill-Gruppe.
// HARTE REGEL: belegbare Namen/Einstufung NUR aus den Wochen-KPIs (weak/strong = Threshold-Band), nie geraten.
// Gibt die Lage keinen datengestützten Anstoß her, greift ein allgemeiner (behauptet nichts Falsches).
// Wechselnd (nie derselbe wie zuletzt), 2–3×/Woche (Mo–Fr, ≥2 Tage Abstand je Leiter). Mail (max@) + Slack.
// Team = (Projekt, Skill); Leiter = Position 'Teamleiter'. Cron: Mo–Fr. Deploy: functions deploy leader-nudges --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { agentBrand, shell, lead, button, metricCard, callout, refLine, PORTAL_URL } from "../_shared/agent_mail.ts";
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

// KPI-Richtung: niedriger = besser?
const LOWER_BETTER: Record<string, boolean> = { AHT: true, ACW: true };
const kpiUnit = (k: string) => k === "AHT" ? " min" : "";
function fmtN(v: any) { return (v == null) ? "" : String(v).replace(".", ","); }

const esc = (s: any) => String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;");

// Strukturierte Analyse der schwachen Agenten (geteilt von Text- und HTML-Ausgabe). Sortiert: verschlechtert ZUERST.
function weakData(weak: any[]): any {
  if (!weak || !weak.length) return null;
  const byKpi: Record<string, any[]> = {};
  weak.forEach((w) => { (byKpi[w.kpi] = byKpi[w.kpi] || []); if (!byKpi[w.kpi].some((x) => x.name === w.name)) byKpi[w.kpi].push(w); });
  const dom = Object.entries(byKpi).sort((a, b) => b[1].length - a[1].length)[0];
  if (!dom) return null;
  const kpi = dom[0]; const low = LOWER_BETTER[kpi]; const unit = kpiUnit(kpi); const teamAvg = dom[1][0].team_avg;
  const agents = dom[1].slice(0, 4).map((a) => {
    let tone = "neutral"; let deltaText = "neu diese Woche";
    if (a.prev != null) { const worse = low ? (a.value > a.prev) : (a.value < a.prev); const same = Math.abs(a.value - a.prev) < (low ? 0.3 : 0.05);
      tone = same ? "neutral" : (worse ? "bad" : "good");
      deltaText = same ? ("≈ wie Vorwoche (" + fmtN(a.prev) + ")") : (worse ? ("schlechter als Vorwoche (" + fmtN(a.prev) + ")") : ("besser als Vorwoche (" + fmtN(a.prev) + ")")); }
    let cause = "";
    if (a.hold_sec != null && a.hold_sec >= 200) cause = "hält im Schnitt lange (" + Math.round(a.hold_sec) + " s)";
    else if (a.acw_sec != null && a.acw_sec >= 150) cause = "lange Nachbearbeitung (" + Math.round(a.acw_sec) + " s ACW)";
    else if (a.tenure_weeks != null && a.tenure_weeks < 8) cause = "erst " + a.tenure_weeks + " Wochen dabei";
    else if (a.last_fb_days == null) cause = "noch kein Feedbackgespräch";
    else if (a.tenure_weeks != null && a.tenure_weeks < 16) cause = a.tenure_weeks + " Wochen dabei";
    return { name: a.name, value: fmtN(a.value), unit, tone, deltaText, cause };
  });
  agents.sort((a, b) => { const rank = (t: string) => t === "bad" ? 0 : t === "neutral" ? 1 : 2; return rank(a.tone) - rank(b.tone); });
  const anyNew = dom[1].some((a) => a.tenure_weeks != null && a.tenure_weeks < 8);
  const anyTime = dom[1].some((a) => (a.hold_sec != null && a.hold_sec >= 200) || (a.acw_sec != null && a.acw_sec >= 150));
  const anyNoFb = dom[1].some((a) => a.last_fb_days == null);
  let lever;
  if (anyNew) lever = "Die Neuen brauchen Begleitung bei der Gesprächsführung – eine Hospitation oder Side-by-Side hilft mehr als Zahlen.";
  else if (anyTime) lever = "Schau mit ihnen, wo die Zeit hingeht: langes Halten und Nachbearbeitung lassen sich gezielt üben.";
  else if (anyNoFb) lever = "Plan mit ihnen ein Feedbackgespräch – die Grundlage fehlt noch.";
  else lever = "Hör dir ein paar ihrer Calls an, dann siehst du, woran es hakt.";
  return { kpi, unit, teamAvg, agents, lever, names: dom[1].slice(0, 3).map((a) => a.name) };
}

// Text-Fassung (Slack) — dieselbe Analyse, ohne Farben.
function weakAnalysis(weak: any[]): string {
  const d = weakData(weak); if (!d) return "";
  const intro = joinUnd(d.names) + " liegen diese Woche bei " + d.kpi + " im kritischen Bereich" + (d.teamAvg != null ? " (Team-Schnitt " + fmtN(d.teamAvg) + d.unit + ")" : "") + ".";
  const lines = d.agents.map((a: any) => a.name + ": " + a.value + a.unit + ", " + a.deltaText + (a.cause ? " – " + a.cause : "") + ".");
  return intro + "\n" + lines.join("\n") + "\n\nWas hilft: " + d.lever;
}

// HTML-Fassung (Mail): farbige Karten je Agent (rot schlechter / grün besser), Team-Schnitt abgesetzt, Was-hilft-Block.
function weakRichHtml(weak: any[], brand: any): string {
  const d = weakData(weak); if (!d) return "";
  let out = lead("<b>" + esc(joinUnd(d.names)) + "</b> liegen diese Woche bei " + esc(d.kpi) + " im kritischen Bereich. Zuerst, wer sich verschlechtert hat:");
  if (d.teamAvg != null) out += refLine("Team-Schnitt " + fmtN(d.teamAvg) + d.unit);
  d.agents.forEach((a: any) => { out += metricCard({ name: a.name, value: a.value, unit: a.unit, deltaText: a.deltaText, tone: a.tone, note: a.cause }); });
  out += callout("Was hilft", d.lever, brand.accent);
  return out;
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
    .replace(/\{weak_analysis\}/g, weakAnalysis(s.weak))
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
      const isWeakRich = pick.template.includes("{weak_analysis}") && (s.weak || []).length;
      const inner = isWeakRich
        ? (weakRichHtml(s.weak, brand) + button(PORTAL_URL, "Zum Team →", brand.accent))
        : (lead(text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/\n/g, "<br>")) + button(PORTAL_URL, "Zum Team →", brand.accent));
      const html = shell(brand, "Ein Anstoß für dein Team", scope, inner);
      const email = previewTo || emailBy[uid];
      if (dry) { results.push({ leader: L.name, scope, key: pick.key, text, html, email }); continue; }
      if (previewTo) { const dk = scope + "|" + pick.key; if (sentPreview.has(dk)) { results.push({ leader: L.name, skipped: "preview-dup" }); continue; } sentPreview.add(dk); }
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
