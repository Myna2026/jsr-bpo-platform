// Coach · Einheiten-Motor v2. Nutzer-JWT identifiziert den Mitarbeiter (get_my_employee_id), geschrieben wird mit Service-Role.
// Grundsätze (User): Wiederholung im richtigen Abstand (Leitner-Kästen in coach_progress, fällige Fragen zuerst), Situationen
// vor Faktenabfrage (free/order/situative mc bevorzugt, Tippen als Drill), Rückmeldung, die weiterhilft (warum die gewählte
// Antwort falsch ist, Merk-Satz, Musterantwort, Kernpunkte getroffen/fehlend). Nie ins Leere: Pool wird in Stufen aufgefüllt.
// Aktionen: start {settings|assignment_id} · answer · finish · history · (preview=true: HR-Probelauf ohne Speichern)
// Deploy: supabase functions deploy coach-session --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL = Deno.env.get("SUPABASE_URL")!, ANON = Deno.env.get("SUPABASE_ANON_KEY")!, SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
const MODEL = "claude-sonnet-5";
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, s = 200) => { if (s >= 400) console.error("[coach-session] " + s + " " + JSON.stringify(b)); return new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } }); };
const norm = (s: any) => String(s ?? "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9@.]+/g, " ").trim();
const digits = (s: any) => String(s ?? "").replace(/\D+/g, "");
const shuffle = <T,>(a: T[]) => { const b = a.slice(); for (let i = b.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [b[i], b[j]] = [b[j], b[i]]; } return b; };
const admin = createClient(SB_URL, SERVICE);
const BOX_DAYS = [1, 1, 3, 7, 14, 30];

function publicQ(q: any) {   // ohne Lösung an den Mitarbeiter
  return { id: q.id, kind: q.kind, difficulty: q.difficulty, topic: q.topic, zielgebiet: q.zielgebiet, prompt: q.prompt,
    options: q.kind === "mc" ? (q.options || []).map((o: any) => ({ key: o.key, text: o.text })) : q.kind === "match" ? q.options : q.kind === "order" ? shuffle(q.options || []) : null };
}
function countFor(minutes: number) { return Math.max(3, Math.min(20, Math.round(minutes * 1.2))); }

// ── Bewertung ─────────────────────────────────────────────────────────────────────────────────────────
function gradeMc(q: any, a: any) { const key = String(q.answer?.key); const chosen = String(a?.key || ""); const ok = chosen === key;
  const opt = (q.options || []).find((o: any) => o.key === chosen); const why = opt && opt.why ? "Deine Wahl (" + chosen + ") ist " + opt.why + "." : "";
  return { points: ok ? 1 : 0, feedback: ok ? "" : ("Nicht ganz. " + why + " Richtig ist " + key + ". " + (q.explanation ? "Merk dir: " + q.explanation : "")).replace(/\s+/g, " ").trim() }; }
function gradeGap(q: any, a: any) {
  const given = String(a?.text || ""); const acc: string[] = q.answer?.accept || [];
  const ok = acc.some((v) => { const dv = digits(v), dg = digits(given); if (dv.length >= 5) return dv === dg; return norm(v) === norm(given); });
  let partial = 0; if (!ok) for (const v of acc) { const dv = digits(v), dg = digits(given); if (dv.length >= 6 && dv.length === dg.length) { let diff = 0; for (let i = 0; i < dv.length; i++) if (dv[i] !== dg[i]) diff++; if (diff === 1) partial = 0.5; } }
  return { points: ok ? 1 : partial, feedback: ok ? "" : partial ? "Fast: eine Ziffer daneben. Richtig ist " + acc[0] + "." : "Richtig ist: " + acc[0] + "." + (q.explanation ? " Merk dir: " + q.explanation : "") };
}
function gradeMatch(q: any, a: any) { const pairs = q.answer?.pairs || {}; const given = a?.pairs || {}; const keys = Object.keys(pairs); const hit = keys.filter((k) => norm(given[k]) === norm(pairs[k])).length; const wrong = keys.filter((k) => norm(given[k]) !== norm(pairs[k]));
  return { points: keys.length ? Math.round(hit / keys.length * 100) / 100 : 0, feedback: hit === keys.length ? "Alles richtig zugeordnet." : hit + " von " + keys.length + " richtig. " + wrong.map((k) => k + " gehört zu " + pairs[k]).join(", ") + "." }; }
function gradeOrder(q: any, a: any) { const seq: string[] = q.answer?.sequence || []; const given: string[] = Array.isArray(a?.sequence) ? a.sequence : []; const hit = seq.filter((s, i) => norm(given[i]) === norm(s)).length;
  const first = seq.findIndex((s, i) => norm(given[i]) !== norm(s));
  return { points: seq.length ? Math.round(hit / seq.length * 100) / 100 : 0, feedback: hit === seq.length ? "Reihenfolge stimmt." : hit + " von " + seq.length + " Schritten an der richtigen Stelle." + (first >= 0 ? " Ab Schritt " + (first + 1) + " weicht es ab: dort kommt „" + seq[first] + "“." : "") }; }

const GRADE_TOOL = { name: "bewertung", input_schema: { type: "object", properties: {
  hits: { type: "array", items: { type: "string" }, description: "Kernpunkte aus der Vorlage, die inhaltlich in der Antwort vorkommen (wörtlich aus der Vorlage übernehmen)" },
  missing: { type: "array", items: { type: "string" }, description: "Kernpunkte aus der Vorlage, die fehlen" },
  feedback: { type: "string", description: "2-3 Sätze an die Kollegin: was gut war, was gefehlt hat und WIE sie es beim nächsten Mal sagt. Konkret, freundlich, duzen. Keine Floskeln." },
  wrong: { type: "boolean", description: "true nur, wenn die Antwort etwas sachlich Falsches behauptet (falsche Nummer, falscher Ablauf)" },
}, required: ["hits", "missing", "feedback", "wrong"] } };
async function gradeFree(q: any, a: any, agentName: string): Promise<{ points: number; feedback: string; rubric: any }> {
  const text = String(a?.text || "").trim(); const must: string[] = q.answer?.must || []; const nice: string[] = q.answer?.nice || [];
  if (!text) return { points: 0, feedback: "Keine Antwort.", rubric: { hits: [], missing: must, model_answer: q.answer?.model_answer || null } };
  if (!ANTHROPIC_KEY) return { points: 0, feedback: "Bewertung gerade nicht möglich.", rubric: { hits: [], missing: must, model_answer: q.answer?.model_answer || null } };
  const system = "Du bist " + agentName + " und coachst eine Kollegin im Call-Center. Du bewertest ihre Antwort auf eine Übungssituation ausschließlich anhand der VORLAGE aus der Unterlage. " +
    "Inhalt zählt, nicht Rechtschreibung oder Grammatik. Ein Kernpunkt gilt als getroffen, wenn er sinngemäß enthalten ist. Erfinde keine Anforderungen, die nicht in der Vorlage stehen. " +
    "Deine Rückmeldung hilft weiter: benenne, was gut war, was gefehlt hat, und sag konkret, wie sie es beim nächsten Mal dem Kunden sagt. Kurz, freundlich, duzen.";
  const user = "SITUATION: " + q.prompt + "\n\nVORLAGE (Kernpunkte, müssen vorkommen):\n- " + must.join("\n- ") + (nice.length ? "\n\nZUSATZ (schön, nicht Pflicht):\n- " + nice.join("\n- ") : "") + (q.answer?.model_answer ? "\n\nMUSTERANTWORT AUS DER UNTERLAGE: " + q.answer.model_answer : "") + "\n\nAUFLÖSUNG: " + (q.explanation || "") + "\n\nANTWORT DER KOLLEGIN:\n" + text;
  const resp = await fetch("https://api.anthropic.com/v1/messages", { method: "POST", headers: { "x-api-key": ANTHROPIC_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({ model: MODEL, max_tokens: 700, system, tools: [GRADE_TOOL], tool_choice: { type: "tool", name: "bewertung" }, messages: [{ role: "user", content: user }] }) });
  const data = await resp.json(); if (!resp.ok) throw new Error(data?.error?.message || String(resp.status));
  const t = (data.content || []).find((c: any) => c.type === "tool_use")?.input || {};
  const words = (x: string) => new Set(norm(x).split(" ").filter((w) => w.length >= 3));
  const same = (a: string, b: string) => { const A = words(a), B = words(b); if (!A.size || !B.size) return false; let hit = 0; for (const w of A) if (B.has(w)) hit++; return hit / Math.min(A.size, B.size) >= 0.6; };
  const mapTo = (list: string[], pool: string[]) => pool.filter((p) => (list || []).some((x: string) => same(x, p)));
  const mustHit = mapTo(t.hits || [], must); const niceHit = mapTo(t.hits || [], nice);
  let points = must.length ? mustHit.length / must.length : 0; if (t.wrong) points = Math.min(points, 0.5);
  return { points: Math.round(points * 100) / 100, feedback: String(t.feedback || ""), rubric: { hits: [...mustHit, ...niceHit], missing: must.filter((m) => !mustHit.includes(m)), model_answer: q.answer?.model_answer || null } };
}

// ── Pool: Stoff-Umfang + Abstand-Wiederholung, in Stufen aufgefüllt ───────────────────────────────────
type PoolInfo = { exact: number; filled: number; fillFrom: string | null; note: string | null; due: number; related: string[]; short: boolean; n: number };
// ── Verwandtschaft von Themen (deterministisch, erklärbar): gemeinsame Wortstämme („Transfer“ in „Gruppentransfer“) oder dieselbe
//    Sinngruppe (Familie ↔ Baby/Kinder/Schwangerschaft). Nur damit wird aufgefüllt; nie mit dem, was gerade da ist.
const T_STOP = new Set(["beim", "bei", "im", "in", "und", "von", "zu", "zum", "zur", "der", "die", "das", "des", "fuer", "mit", "vor", "ort", "ohne", "via", "coaching", "ablaeufe", "werkzeuge", "prozess", "leitfaeden", "sonderfaelle", "sonderprozesse", "kontakt", "v2", "v3", "und", "kunde", "reisen", "gmbh"]);
const T_CLUSTERS: string[][] = [
  ["transfer", "ruecktransfer", "shuttle", "anreise", "abholung", "nachtankunft"],
  ["baby", "kleinkind", "kind", "kinder", "familie", "schwangerschaft", "schwanger", "allein reisend"],
  ["gepaeck", "handgepaeck", "koffer", "sondergepaeck", "freigepaeck"],
  ["storno", "stornierung", "stornogebuehren", "umbuchung", "ruecktritt", "no-show", "noshow", "fristen", "teilstorno"],
  ["flug", "flugzeiten", "airline", "airlines", "check-in", "checkin", "flugaenderung", "flugplan", "web-check-in", "flugprobleme", "fliegen", "erstattung"],
  ["zahlung", "rechnung", "restzahlung", "anzahlung", "zahlungsverzug", "mahnstufe", "zahlungsarten", "reisebestaetigung"],
  ["notfall", "notfallnummer", "reiseabbruch", "agentur vor ort"],
  ["sonderfaelle", "sonderprozesse", "mobilitaetshilfen", "haustiere", "haftung", "schwangerschaft"],
  ["hotel", "zimmer", "hotelsupplier", "unterkunft", "hotelgutschein", "angebotsverfuegbarkeit"],
  ["dokumente", "reiseunterlagen", "reisedokumente", "sicherungsschein", "passagierdaten", "buchungsbestaetigung", "namensaenderung", "vorgangsnummer", "unterlagen"],
  ["veranstalter", "reiseveranstalter", "veranstalterwechsel", "ota", "holidays.ch", "condor holidays"],
  ["peakwork", "midoco", "travelviewer", "lpac", "einbuchen", "fulfillment", "einpflegen"],
  ["gespraechsfuehrung", "telefonverhalten", "leitfaeden", "textvorlagen", "faq"],
];
const tNorm = (t: string) => norm(t).replace(/ä/g, "ae").replace(/ö/g, "oe").replace(/ü/g, "ue").replace(/ß/g, "ss");
const tTokens = (t: string) => tNorm(t).split(/[^a-z0-9.-]+/).filter((w) => w.length >= 4 && !T_STOP.has(w));
const tClusters = (t: string) => { const n = tNorm(t); const out: number[] = []; T_CLUSTERS.forEach((c, i) => { if (c.some((w) => n.includes(w))) out.push(i); }); return out; };
// 0 = fremd · 1 = gleiche Sinngruppe · 2 = gemeinsamer Wortstamm (z. B. „Transfer“)
function topicRelation(a: string, b: string): number {
  if (a === b) return 3;
  const ta = tTokens(a), tb = tTokens(b);
  if (ta.some((x) => tb.some((y) => x === y || (x.length >= 5 && y.includes(x)) || (y.length >= 5 && x.includes(y))))) return 2;
  const ca = tClusters(a), cb = tClusters(b); if (ca.some((c) => cb.includes(c))) return 1;
  return 0;
}
async function buildPool(pid: string, s: any, n: number, kinds: string[], diff: string, settings: any, progress: Map<string, any>): Promise<{ list: any[]; info: PoolInfo }> {
  const hidden: string[] = (settings && settings.hidden_topics) || []; const allowedK: string[] = (settings && settings.allowed_kinds) || ["mc", "gap", "match", "order", "free"];
  const { data: all } = await admin.from("coach_questions").select("id,kind,difficulty,topic,zielgebiet,prompt").eq("project_id", pid).eq("status", "active").in("kind", allowedK).limit(5000);
  const rows: any[] = (all || []).filter((x) => !hidden.includes(x.topic));
  const topic = s.mode === "topic" && s.topic ? String(s.topic) : null;
  const zg = s.mode === "sprint" && s.zielgebiet ? norm(String(s.zielgebiet)) : null;
  const zgRe = zg ? new RegExp("(^|[^a-z0-9])" + zg.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "([^a-z0-9]|$)") : null;
  const inScope = (x: any) => topic ? x.topic === topic : zgRe ? (zgRe.test(norm(x.zielgebiet || "")) || zgRe.test(norm(x.prompt))) : true;
  // Zielgebiet: dieselbe Region (kb_regions: Insel/Region ↔ Orte) gilt als verwandt, z. B. Heraklion ↔ Kreta
  let regionMates: Set<string> | null = null;
  if (zg) { const { data: regs } = await admin.from("kb_regions").select("name,aliases,members").eq("project_id", pid).eq("status", "active");
    const hit = (regs || []).filter((r: any) => [r.name, ...(r.aliases || []), ...(r.members || [])].some((m: string) => norm(m) === zg || zgRe!.test(norm(m))));
    if (hit.length) regionMates = new Set(hit.flatMap((r: any) => [r.name, ...(r.aliases || []), ...(r.members || [])]).map((m: string) => norm(m))); }
  const sameRegion = (x: any) => !!regionMates && !!x.zielgebiet && !inScope(x) && [...regionMates].some((m) => norm(x.zielgebiet) === m || norm(x.zielgebiet).includes(m));
  const relScore: Record<string, number> = {}; if (topic) for (const x of rows) if (!(x.topic in relScore)) relScore[x.topic] = topicRelation(topic, x.topic);
  const related = (x: any) => topic ? (relScore[x.topic] || 0) > 0 && x.topic !== topic : sameRegion(x);
  const tiers: { f: (x: any) => boolean; label: string | null }[] = (topic || zg) ? [
    { f: (x) => inScope(x) && (diff === "mix" || x.difficulty === diff) && kinds.includes(x.kind), label: null },
    { f: (x) => inScope(x) && (diff === "mix" || x.difficulty === diff), label: "anderer Frageart" },
    { f: (x) => inScope(x), label: diff === "mix" ? null : "anderer Stufe" },
    { f: (x) => related(x) && (diff === "mix" || x.difficulty === diff) && kinds.includes(x.kind), label: topic ? "verwandten Themen" : "derselben Region" },
    { f: (x) => related(x), label: topic ? "verwandten Themen" : "derselben Region" },
  ] : [ { f: () => true, label: null } ];
  const now = Date.now();
  // Reihenfolge innerhalb einer Stufe: fällige Wiederholungen, dann Neues, dann nicht Fälliges; bei verwandten Themen die näheren zuerst
  const rank = (x: any) => { const p = progress.get(x.id); const due = p ? new Date(p.next_due).getTime() <= now : false; const isNew = !p;
    const near = topic ? (3 - (relScore[x.topic] || 0)) * 30 : 0;
    return (due ? 0 : isNew ? 1 : 2) * 100 + near + Math.random() * 25; };
  // Zwei Kontingente: Freitext höchstens ein Drittel, der Rest andere Arten. Beide stufenweise füllen (exakt zuerst, darin fällig vor neu).
  const capFree = Math.max(1, Math.floor(n / 3)); const free: any[] = []; const rest: any[] = []; const seen = new Set<string>(); const seenPrompt = new Set<string>();
  const quotasFull = () => free.length >= capFree && rest.length >= n;
  const push = (x: any, tier: number) => { const k = norm(x.prompt); if (seenPrompt.has(k)) { seen.add(x.id); return; } const isFree = x.kind === "free"; if (isFree ? free.length >= capFree : rest.length >= n) return; seenPrompt.add(k); seen.add(x.id); (isFree ? free : rest).push({ ...x, _tier: tier }); };
  for (let i = 0; i < tiers.length && !quotasFull(); i++) {
    const t = tiers[i]; let cand = rows.filter((x) => !seen.has(x.id) && t.f(x)).sort((a, b) => rank(a) - rank(b));
    if (i >= 3) { // Verwandtes: über die Themen verteilen (reihum), damit nicht ein großes Nachbarthema alles füllt
      const groups = new Map<string, any[]>(); for (const x of cand) { const k = topic ? x.topic : (x.zielgebiet || ""); (groups.get(k) || groups.set(k, []).get(k))!.push(x); }
      const order = [...groups.keys()].sort((a, b) => (topic ? (relScore[b] || 0) - (relScore[a] || 0) : 0)); const rr: any[] = [];
      for (let k = 0; rr.length < cand.length; k++) for (const g of order) { const arr = groups.get(g)!; if (arr[k]) rr.push(arr[k]); }
      cand = rr; }
    for (const x of cand) { if (quotasFull()) break; push(x, i); }
  }
  // Gibt es nicht genug Passendes: lieber eine kurze Einheit als beliebige Fragen
  const restPick = rest.slice(0, n - Math.min(free.length, capFree));
  let chosen = [...restPick, ...free.slice(0, n - restPick.length)].slice(0, n);
  const short = chosen.length < n;
  // Reihenfolge: Thema zuerst, dann Verwandtes; innerhalb einer Stufe gemischt, Freitext jeweils am Ende
  const inTier = (t: number) => { const g = chosen.filter((x) => x._tier === t); return [...shuffle(g.filter((x) => x.kind !== "free")), ...g.filter((x) => x.kind === "free")]; };
  chosen = [...new Set(chosen.map((x) => x._tier))].sort((a, b) => a - b).flatMap(inTier);
  const exact = chosen.filter((x) => x._tier <= 2).length; const filledFrom = chosen.filter((x) => x._tier > 2);
  const relatedTopics = [...new Set(filledFrom.map((x) => topic ? x.topic : x.zielgebiet).filter(Boolean))] as string[];
  const fillFrom = filledFrom.length ? (tiers[filledFrom[0]._tier].label) : null;
  const scopeLabel = topic ? "„" + topic + "“" : zg ? "„" + s.zielgebiet + "“" : null;
  const note = !scopeLabel ? null
    : (exact >= n) ? null
    : (filledFrom.length ? "Zu " + scopeLabel + " gibt es " + exact + " passende Frage" + (exact === 1 ? "" : "n") + ", dazu " + filledFrom.length + " aus " + (topic ? "verwandten Themen (" + relatedTopics.slice(0, 3).join(", ") + (relatedTopics.length > 3 ? ", …" : "") + ")" : "derselben Region (" + relatedTopics.slice(0, 3).join(", ") + ")") + "."
      : "Zu " + scopeLabel + " gibt es nur " + chosen.length + " passende Frage" + (chosen.length === 1 ? "" : "n") + ", deshalb ist die Einheit kürzer.");
  const ids = chosen.map((x) => x.id); const { data: full } = await admin.from("coach_questions").select("*").in("id", ids);
  const byId: Record<string, any> = {}; for (const r of (full || [])) byId[r.id] = r;
  const list = ids.map((id) => byId[id]).filter(Boolean);
  return { list, info: { exact: Math.min(exact, list.length), filled: filledFrom.length, fillFrom, note, related: relatedTopics, short, n: list.length, due: list.filter((x) => { const p = progress.get(x.id); return p && new Date(p.next_due).getTime() <= now; }).length } };
}
async function loadProgress(empId: string): Promise<Map<string, any>> { const { data } = await admin.from("coach_progress").select("question_id,box,next_due,seen,correct").eq("employee_id", empId); const m = new Map<string, any>(); for (const r of (data || [])) m.set(r.question_id, r); return m; }
async function bumpProgress(empId: string, qid: string, points: number) {
  const { data: p } = await admin.from("coach_progress").select("box,seen,correct").eq("employee_id", empId).eq("question_id", qid).maybeSingle();
  const ok = points >= 0.99; const box = ok ? Math.min(5, ((p && p.box) || 0) + 1) : 0; const days = BOX_DAYS[box] || 1;
  await admin.from("coach_progress").upsert({ employee_id: empId, question_id: qid, box, next_due: new Date(Date.now() + days * 864e5).toISOString(), seen: ((p && p.seen) || 0) + 1, correct: ((p && p.correct) || 0) + (ok ? 1 : 0), last_points: points, updated_at: new Date().toISOString() });
  return { box, next_days: days };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const auth = req.headers.get("Authorization") || ""; if (!auth) return json({ error: "Nicht angemeldet." }, 401);
  const user = createClient(SB_URL, ANON, { global: { headers: { Authorization: auth } } });
  const { data: u } = await user.auth.getUser(); if (!u?.user?.id) return json({ error: "Sitzung ungültig, bitte Seite neu laden." }, 401);
  let body: any = {}; try { body = await req.json(); } catch { /* egal */ }
  const action = String(body.action || "");
  const settingsFor = async (pid: string) => (await admin.from("coach_settings").select("*").eq("project_id", pid).maybeSingle()).data || {};

  // ── Probelauf (HR/Teamleitung): keine Speicherung; Zugriff = darf die Fragen des Partners lesen ──
  if (body.preview === true) {
    const ppid = String(body.project_id || ""); if (!ppid) return json({ error: "Kein Partner angegeben." }, 400);
    const { count } = await user.from("coach_questions").select("id", { count: "exact", head: true }).eq("project_id", ppid).eq("status", "active");
    if (!count) return json({ error: "Kein Zugriff oder für diesen Partner gibt es noch keine Fragen." }, 403);
    const { data: ppa } = await admin.from("partner_agents").select("name").eq("project_id", ppid).maybeSingle(); const pAgent = ppa?.name || "Coach";
    if (action === "start" || action === "plan") {
      const s = body.settings || {}; const settings = await settingsFor(ppid); const minutes = [2, 5, 10, 15].includes(Number(s.minutes)) ? Number(s.minutes) : (settings.default_minutes || 5); const n = countFor(minutes);
      const diff = ["leicht", "mittel", "schwer", "mix"].includes(s.difficulty) ? s.difficulty : (settings.default_difficulty || "mix");
      const kinds: string[] = Array.isArray(s.kinds) && s.kinds.length ? s.kinds : ["mc", "gap", "match", "order", "free"];
      const { list, info } = await buildPool(ppid, s, n, kinds, diff, settings, new Map());
      if (action === "plan") return json({ ok: true, plan: { n: info.n, exact: info.exact, filled: info.filled, related: info.related, short: info.short, note: info.note, minutes, wanted: n } });
      if (!list.length) return json({ error: "Für diesen Partner gibt es noch keine Übungsfragen." }, 404);
      return json({ ok: true, session_id: null, preview: true, agent: pAgent, fill: info, minutes: info.short ? Math.max(1, Math.ceil(list.length / 1.2)) : minutes, questions: list.map(publicQ) });
    }
    if (action === "answer") {
      const { data: q } = await admin.from("coach_questions").select("*").eq("id", body.question_id).eq("project_id", ppid).maybeSingle(); if (!q) return json({ error: "Frage fehlt." }, 404);
      let g: any; try { g = q.kind === "mc" ? gradeMc(q, body.answer) : q.kind === "gap" ? gradeGap(q, body.answer) : q.kind === "match" ? gradeMatch(q, body.answer) : q.kind === "order" ? gradeOrder(q, body.answer) : await gradeFree(q, body.answer, pAgent); }
      catch (e) { return json({ error: "Bewertung fehlgeschlagen: " + (e as Error).message }, 502); }
      return json({ ok: true, answer_id: null, points: g.points, feedback: g.feedback, rubric: g.rubric || null, solution: q.answer, options_why: q.kind === "mc" ? q.options : null, explanation: q.explanation, source: q.source_label, topic: q.topic });
    }
    if (action === "finish") { const rows: any[] = Array.isArray(body.results) ? body.results : []; const points = rows.reduce((a, r) => a + Number(r.points || 0), 0); const max = rows.length;
      const topics: Record<string, { points: number; max: number }> = {}; for (const r of rows) { const t = topics[r.topic] = topics[r.topic] || { points: 0, max: 0 }; t.points += Number(r.points || 0); t.max += 1; }
      const weakest = Object.entries(topics).sort((a, b) => a[1].points / a[1].max - b[1].points / b[1].max)[0];
      return json({ ok: true, points, max, score: max ? Math.round(points / max * 100) / 100 : 0, topics, recommend: weakest && weakest[1].points / weakest[1].max < 1 ? weakest[0] : null, strong: null, preview: true }); }
    if (action === "history") return json({ ok: true, sessions: [], topics: {}, agent: pAgent, preview: true, streak: 0, due: 0 });
    return json({ error: "Unbekannte Aktion." }, 400);
  }

  const { data: empId } = await user.rpc("get_my_employee_id"); if (!empId) return json({ error: "Dein Zugang ist mit keinem Mitarbeiter-Datensatz verknüpft, bitte an HR wenden." }, 403);
  const { data: emp } = await admin.from("employees").select("id,project_id,first_name").eq("id", empId).maybeSingle();
  if (!emp?.project_id) return json({ error: "Für deinen Zugang ist kein Projekt hinterlegt." }, 403);
  const pid = emp.project_id;
  const { data: pa } = await admin.from("partner_agents").select("name").eq("project_id", pid).maybeSingle(); const agentName = pa?.name || "Coach";

  if (action === "start" || action === "plan") {
    let s = body.settings || {}; let assignment: any = null; const settings = await settingsFor(pid);
    if (body.assignment_id) {
      const { data: as } = await admin.from("coach_assignments").select("*").eq("id", body.assignment_id).eq("employee_id", empId).eq("status", "open").maybeSingle();
      if (!as) return json({ error: "Diese Pflichteinheit gibt es nicht mehr oder sie ist schon erledigt." }, 404);
      assignment = as; s = { mode: as.topic ? "topic" : (as.zielgebiet ? "sprint" : "daily"), topic: as.topic, zielgebiet: as.zielgebiet, minutes: as.minutes, difficulty: as.difficulty, kinds: null };
    }
    const minutes = [2, 5, 10, 15].includes(Number(s.minutes)) ? Number(s.minutes) : (settings.default_minutes || 5); const n = countFor(minutes);
    const diff = ["leicht", "mittel", "schwer", "mix"].includes(s.difficulty) ? s.difficulty : (settings.default_difficulty || "mix");
    const kinds: string[] = Array.isArray(s.kinds) && s.kinds.length ? s.kinds.filter((k: string) => ["mc", "gap", "match", "order", "free"].includes(k)) : ["mc", "gap", "match", "order", "free"];
    const progress = await loadProgress(empId);
    const { list, info } = await buildPool(pid, s, n, kinds, diff, settings, progress);
    if (action === "plan") return json({ ok: true, plan: { n: info.n, exact: info.exact, filled: info.filled, related: info.related, short: info.short, note: info.note, minutes, wanted: n } });
    if (!list.length) return json({ error: "Für dein Projekt gibt es noch keine Übungsfragen." }, 404);
    const { data: sess, error } = await admin.from("coach_sessions").insert({ employee_id: empId, project_id: pid, user_id: u.user.id, assignment_id: assignment ? assignment.id : null, settings: { mode: s.mode || "daily", topic: s.topic || null, zielgebiet: s.zielgebiet || null, minutes, difficulty: diff, kinds, assignment: assignment ? { id: assignment.id, by: assignment.assigned_by_name, note: assignment.note } : null }, question_ids: list.map((x) => x.id) }).select("id").single();
    if (error) return json({ error: error.message }, 500);
    return json({ ok: true, session_id: sess.id, agent: agentName, minutes: info.short ? Math.max(1, Math.ceil(list.length / 1.2)) : minutes, fill: { exact: info.exact, note: info.note, due: info.due }, assignment: assignment ? { id: assignment.id, topic: assignment.topic, by: assignment.assigned_by_name, note: assignment.note } : null, questions: list.map(publicQ) });
  }

  if (action === "answer") {
    const { data: sess } = await admin.from("coach_sessions").select("id,employee_id,status,question_ids").eq("id", body.session_id).maybeSingle();
    if (!sess || sess.employee_id !== empId) return json({ error: "Einheit nicht gefunden." }, 404);
    if (sess.status !== "open") return json({ error: "Einheit ist abgeschlossen." }, 409);
    if (!(sess.question_ids || []).includes(body.question_id)) return json({ error: "Frage gehört nicht zur Einheit." }, 400);
    const { data: prev } = await admin.from("coach_answers").select("id").eq("session_id", sess.id).eq("question_id", body.question_id).maybeSingle(); if (prev) return json({ error: "Schon beantwortet." }, 409);
    const { data: q } = await admin.from("coach_questions").select("*").eq("id", body.question_id).maybeSingle(); if (!q) return json({ error: "Frage fehlt." }, 404);
    let g: any;
    try { g = q.kind === "mc" ? gradeMc(q, body.answer) : q.kind === "gap" ? gradeGap(q, body.answer) : q.kind === "match" ? gradeMatch(q, body.answer) : q.kind === "order" ? gradeOrder(q, body.answer) : await gradeFree(q, body.answer, agentName); }
    catch (e) { return json({ error: "Bewertung fehlgeschlagen: " + (e as Error).message }, 502); }
    const { data: ans, error } = await admin.from("coach_answers").insert({ session_id: sess.id, question_id: q.id, employee_id: empId, project_id: pid, kind: q.kind, topic: q.topic, answer: body.answer ?? null, points: g.points, max_points: 1, feedback: g.feedback, rubric: g.rubric || null, seconds: Number.isFinite(body.seconds) ? Number(body.seconds) : null }).select("id").single();
    if (error) return json({ error: error.message }, 500);
    const prog = await bumpProgress(empId, q.id, g.points);
    return json({ ok: true, answer_id: ans.id, points: g.points, feedback: g.feedback, rubric: g.rubric || null, solution: q.answer, options_why: q.kind === "mc" ? q.options : null, explanation: q.explanation, source: q.source_label, topic: q.topic, progress: prog });
  }

  if (action === "finish") {
    const { data: sess } = await admin.from("coach_sessions").select("*").eq("id", body.session_id).maybeSingle();
    if (!sess || sess.employee_id !== empId) return json({ error: "Einheit nicht gefunden." }, 404);
    const { data: answers } = await admin.from("coach_answers").select("topic,points,max_points,kind").eq("session_id", sess.id);
    const rows = answers || []; const points = rows.reduce((a: number, r: any) => a + Number(r.points), 0); const max = rows.length;
    const topics: Record<string, { points: number; max: number }> = {}; for (const r of rows) { const t = topics[r.topic] = topics[r.topic] || { points: 0, max: 0 }; t.points += Number(r.points); t.max += 1; }
    const score = max ? Math.round(points / max * 100) / 100 : 0;
    await admin.from("coach_sessions").update({ status: rows.length ? "done" : "abandoned", points, max_points: max, score, topic_scores: topics, finished_at: new Date().toISOString() }).eq("id", sess.id);
    if (sess.assignment_id && rows.length) await admin.from("coach_assignments").update({ status: "done", session_id: sess.id, done_at: new Date().toISOString() }).eq("id", sess.assignment_id).eq("status", "open");
    const weakest = Object.entries(topics).filter(([, v]) => v.max > 0).sort((a, b) => a[1].points / a[1].max - b[1].points / b[1].max)[0];
    const strongest = Object.entries(topics).filter(([, v]) => v.max > 0 && v.points / v.max >= 0.99)[0];
    // Streak: aufeinanderfolgende Tage mit einer abgeschlossenen Einheit
    const { data: days } = await admin.from("coach_sessions").select("finished_at").eq("employee_id", empId).eq("status", "done").order("finished_at", { ascending: false }).limit(60);
    const ds = [...new Set((days || []).map((x: any) => String(x.finished_at).slice(0, 10)))]; let streak = 0; const d0 = new Date(); for (let i = 0; i < 60; i++) { const key = new Date(d0.getTime() - i * 864e5).toISOString().slice(0, 10); if (ds.includes(key)) streak++; else if (i > 0) break; }
    const { count: due } = await admin.from("coach_progress").select("question_id", { count: "exact", head: true }).eq("employee_id", empId).lte("next_due", new Date().toISOString());
    return json({ ok: true, points, max, score, topics, recommend: weakest && weakest[1].points / weakest[1].max < 1 ? weakest[0] : null, strong: strongest ? strongest[0] : null, streak, due: due || 0 });
  }

  if (action === "history") {
    const { data: sessions } = await admin.from("coach_sessions").select("id,settings,points,max_points,score,topic_scores,started_at,finished_at,status").eq("employee_id", empId).eq("status", "done").order("finished_at", { ascending: false }).limit(30);
    const since = new Date(Date.now() - 30 * 864e5).toISOString();
    const { data: answers } = await admin.from("coach_answers").select("topic,points,max_points").eq("employee_id", empId).gte("answered_at", since);
    const topics: Record<string, { points: number; max: number }> = {}; for (const r of (answers || [])) { const t = topics[r.topic] = topics[r.topic] || { points: 0, max: 0 }; t.points += Number(r.points); t.max += 1; }
    const ds = [...new Set((sessions || []).map((x: any) => String(x.finished_at).slice(0, 10)))]; let streak = 0; const d0 = new Date(); for (let i = 0; i < 60; i++) { const key = new Date(d0.getTime() - i * 864e5).toISOString().slice(0, 10); if (ds.includes(key)) streak++; else if (i > 0) break; }
    const { count: due } = await admin.from("coach_progress").select("question_id", { count: "exact", head: true }).eq("employee_id", empId).lte("next_due", new Date().toISOString());
    const { count: learned } = await admin.from("coach_progress").select("question_id", { count: "exact", head: true }).eq("employee_id", empId).gte("box", 3);
    return json({ ok: true, sessions: sessions || [], topics, agent: agentName, streak, due: due || 0, learned: learned || 0 });
  }
  return json({ error: "Unbekannte Aktion." }, 400);
});
