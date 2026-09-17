// Coach · Schnitt 3: Einheiten-Motor. Nutzer-JWT identifiziert den Mitarbeiter (get_my_employee_id), geschrieben wird
// mit Service-Role (sessions/answers haben keine Schreib-Policies). Aktionen:
//   start   {settings:{mode daily|topic|sprint, topic, zielgebiet, minutes, difficulty leicht|mittel|schwer|mix, kinds[]}}
//           → stellt die Einheit zusammen (Dauer → Anzahl; Schwächen bevorzugt; nichts, was in 7 Tagen richtig war), ohne Lösungen
//   answer  {session_id, question_id, answer, seconds} → wertet aus (mc/gap/match/order deterministisch, free durch Conny mit
//           Vorlage aus der Quelle, Teilpunkte, Sprachfehler zählen nicht) und gibt Auflösung + Quelle zurück
//   finish  {session_id} → Ergebnis je Thema, Empfehlung (schwächstes Thema)
//   history → letzte Einheiten + Themen-Schnitt des Mitarbeiters
//   Pflichteinheit: start {assignment_id} nimmt Thema/Dauer/Schwierigkeit aus coach_assignments (keine Wahl), finish setzt sie auf done.
//   Probelauf (HR): body.preview=true + project_id → wer die Fragen des Partners lesen darf (RLS), bekommt dieselbe Einheit,
//   nichts wird gespeichert; grade bewertet zustandslos. So sehen wir, was die Leute bekommen.
// Deploy: supabase functions deploy coach-session --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL = Deno.env.get("SUPABASE_URL")!, ANON = Deno.env.get("SUPABASE_ANON_KEY")!, SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
const MODEL = "claude-sonnet-5";
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const norm = (s: any) => String(s ?? "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9@.]+/g, " ").trim();
const digits = (s: any) => String(s ?? "").replace(/\D+/g, "");
const shuffle = <T,>(a: T[]) => { const b = a.slice(); for (let i = b.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [b[i], b[j]] = [b[j], b[i]]; } return b; };
const admin = createClient(SB_URL, SERVICE);

function publicQ(q: any) {   // ohne Lösung an den Mitarbeiter
  return { id: q.id, kind: q.kind, difficulty: q.difficulty, topic: q.topic, zielgebiet: q.zielgebiet, prompt: q.prompt,
    options: q.kind === "mc" ? q.options : q.kind === "match" ? q.options : q.kind === "order" ? shuffle(q.options || []) : null };
}
function countFor(minutes: number) { return Math.max(3, Math.min(20, Math.round(minutes * 1.2))); }

function gradeMc(q: any, a: any) { const ok = String(a?.key || "") === String(q.answer?.key); return { points: ok ? 1 : 0, feedback: ok ? "Richtig." : "Nicht ganz. Richtig ist " + q.answer.key + "." }; }
function gradeGap(q: any, a: any) {
  const given = String(a?.text || ""); const acc: string[] = q.answer?.accept || [];
  const ok = acc.some((v) => { const dv = digits(v), dg = digits(given); if (dv.length >= 5) return dv === dg; return norm(v) === norm(given); });
  // Teilpunkt: Ziffern fast richtig (eine Ziffer daneben)
  let partial = 0; if (!ok) for (const v of acc) { const dv = digits(v), dg = digits(given); if (dv.length >= 6 && dv.length === dg.length) { let diff = 0; for (let i = 0; i < dv.length; i++) if (dv[i] !== dg[i]) diff++; if (diff === 1) partial = 0.5; } }
  return { points: ok ? 1 : partial, feedback: ok ? "Richtig." : partial ? "Fast: eine Ziffer daneben. Richtig ist " + acc[0] + "." : "Richtig ist: " + acc[0] + "." };
}
function gradeMatch(q: any, a: any) { const pairs = q.answer?.pairs || {}; const given = a?.pairs || {}; const keys = Object.keys(pairs); const hit = keys.filter((k) => norm(given[k]) === norm(pairs[k])).length; return { points: keys.length ? Math.round(hit / keys.length * 100) / 100 : 0, feedback: hit === keys.length ? "Alles richtig zugeordnet." : hit + " von " + keys.length + " richtig." }; }
function gradeOrder(q: any, a: any) { const seq: string[] = q.answer?.sequence || []; const given: string[] = Array.isArray(a?.sequence) ? a.sequence : []; const hit = seq.filter((s, i) => norm(given[i]) === norm(s)).length; return { points: seq.length ? Math.round(hit / seq.length * 100) / 100 : 0, feedback: hit === seq.length ? "Reihenfolge stimmt." : hit + " von " + seq.length + " Schritten an der richtigen Stelle." }; }

const GRADE_TOOL = { name: "bewertung", input_schema: { type: "object", properties: {
  hits: { type: "array", items: { type: "string" }, description: "Kernpunkte aus der Vorlage, die inhaltlich in der Antwort vorkommen (wörtlich aus der Vorlage übernehmen)" },
  missing: { type: "array", items: { type: "string" }, description: "Kernpunkte aus der Vorlage, die fehlen" },
  feedback: { type: "string", description: "1-2 Sätze an die Kollegin, freundlich, konkret: was gut war, was gefehlt hat. Duzen." },
  wrong: { type: "boolean", description: "true nur, wenn die Antwort etwas sachlich Falsches behauptet (falsche Nummer, falscher Ablauf)" },
}, required: ["hits", "missing", "feedback", "wrong"] } };
async function gradeFree(q: any, a: any, agentName: string): Promise<{ points: number; feedback: string; rubric: any }> {
  const text = String(a?.text || "").trim(); const must: string[] = q.answer?.must || []; const nice: string[] = q.answer?.nice || [];
  if (!text) return { points: 0, feedback: "Keine Antwort.", rubric: { hits: [], missing: must } };
  if (!ANTHROPIC_KEY) return { points: 0, feedback: "Bewertung gerade nicht möglich.", rubric: { hits: [], missing: must } };
  const system = "Du bist " + agentName + " und bewertest die Antwort einer Kollegin auf eine Übungsfrage, ausschließlich anhand der VORLAGE aus der Unterlage. " +
    "Inhalt zählt, nicht Rechtschreibung oder Grammatik. Ein Kernpunkt gilt als getroffen, wenn er sinngemäß enthalten ist. Erfinde keine zusätzlichen Anforderungen. Kurz, freundlich, duzen.";
  const user = "FRAGE: " + q.prompt + "\n\nVORLAGE (Kernpunkte, müssen vorkommen):\n- " + must.join("\n- ") + (nice.length ? "\n\nZUSATZ (schön, nicht Pflicht):\n- " + nice.join("\n- ") : "") + "\n\nAUFLÖSUNG AUS DER UNTERLAGE: " + (q.explanation || "") + "\n\nANTWORT DER KOLLEGIN:\n" + text;
  const resp = await fetch("https://api.anthropic.com/v1/messages", { method: "POST", headers: { "x-api-key": ANTHROPIC_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({ model: MODEL, max_tokens: 600, system, tools: [GRADE_TOOL], tool_choice: { type: "tool", name: "bewertung" }, messages: [{ role: "user", content: user }] }) });
  const data = await resp.json(); if (!resp.ok) throw new Error(data?.error?.message || String(resp.status));
  const t = (data.content || []).find((c: any) => c.type === "tool_use")?.input || {};
  // Kernpunkte der Vorlage zuordnen, auch wenn die KI sie leicht umformuliert zurückgibt (Wort-Überlappung ≥ 60 %)
  const words = (x: string) => new Set(norm(x).split(" ").filter((w) => w.length >= 3));
  const same = (a: string, b: string) => { const A = words(a), B = words(b); if (!A.size || !B.size) return false; let hit = 0; for (const w of A) if (B.has(w)) hit++; return hit / Math.min(A.size, B.size) >= 0.6; };
  const mapTo = (list: string[], pool: string[]) => pool.filter((p) => (list || []).some((x: string) => same(x, p)));
  const mustHit = mapTo(t.hits || [], must); const niceHit = mapTo(t.hits || [], nice);
  let points = must.length ? mustHit.length / must.length : 0; if (t.wrong) points = Math.min(points, 0.5);
  return { points: Math.round(points * 100) / 100, feedback: String(t.feedback || ""), rubric: { hits: [...mustHit, ...niceHit], missing: must.filter((m) => !mustHit.includes(m)) } };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const auth = req.headers.get("Authorization") || ""; if (!auth) return json({ error: "Nicht angemeldet." }, 401);
  const user = createClient(SB_URL, ANON, { global: { headers: { Authorization: auth } } });
  const { data: u } = await user.auth.getUser(); if (!u?.user?.id) return json({ error: "Sitzung ungültig." }, 401);
  let body: any = {}; try { body = await req.json(); } catch { /* egal */ }
  const action = String(body.action || "");
  // ── Probelauf (HR/Teamleitung): keine Speicherung, Zugriff = darf die Fragen des Partners lesen ──
  if (body.preview === true) {
    const ppid = String(body.project_id || ""); if (!ppid) return json({ error: "Kein Partner angegeben." }, 400);
    const { count } = await user.from("coach_questions").select("id", { count: "exact", head: true }).eq("project_id", ppid).eq("status", "active");
    if (!count) return json({ error: "Kein Zugriff oder keine Fragen für diesen Partner." }, 403);
    const { data: ppa } = await admin.from("partner_agents").select("name").eq("project_id", ppid).maybeSingle(); const pAgent = ppa?.name || "Coach";
    if (action === "start") {
      const s = body.settings || {}; const minutes = [2, 5, 10, 15].includes(Number(s.minutes)) ? Number(s.minutes) : 5; const n = countFor(minutes);
      const diff = ["leicht", "mittel", "schwer", "mix"].includes(s.difficulty) ? s.difficulty : "mix";
      const kinds: string[] = Array.isArray(s.kinds) && s.kinds.length ? s.kinds : ["mc", "gap", "match", "order", "free"];
      let q = admin.from("coach_questions").select("*").eq("project_id", ppid).eq("status", "active").in("kind", kinds);
      if (diff !== "mix") q = q.eq("difficulty", diff); if (s.mode === "topic" && s.topic) q = q.eq("topic", String(s.topic));
      if (s.mode === "sprint" && s.zielgebiet) q = q.or("zielgebiet.ilike.%" + String(s.zielgebiet).replace(/[%,()]/g, "") + "%,prompt.ilike.%" + String(s.zielgebiet).replace(/[%,()]/g, "") + "%");
      const { data: pool } = await q.limit(2000); if (!pool || !pool.length) return json({ error: "Dazu gibt es noch keine Übungsfragen." }, 404);
      const capFree = Math.max(1, Math.floor(n / 3)); const free = shuffle(pool.filter((x: any) => x.kind === "free")).slice(0, capFree); const rest = shuffle(pool.filter((x: any) => x.kind !== "free")).slice(0, n - free.length);
      return json({ ok: true, session_id: null, preview: true, agent: pAgent, questions: [...rest, ...free].slice(0, n).map(publicQ) });
    }
    if (action === "answer") {
      const { data: q } = await admin.from("coach_questions").select("*").eq("id", body.question_id).eq("project_id", ppid).maybeSingle(); if (!q) return json({ error: "Frage fehlt." }, 404);
      let g: any; try { g = q.kind === "mc" ? gradeMc(q, body.answer) : q.kind === "gap" ? gradeGap(q, body.answer) : q.kind === "match" ? gradeMatch(q, body.answer) : q.kind === "order" ? gradeOrder(q, body.answer) : await gradeFree(q, body.answer, pAgent); }
      catch (e) { return json({ error: "Bewertung fehlgeschlagen: " + (e as Error).message }, 502); }
      return json({ ok: true, answer_id: null, points: g.points, feedback: g.feedback, rubric: g.rubric || null, solution: q.answer, explanation: q.explanation, source: q.source_label, topic: q.topic });
    }
    if (action === "finish") { const rows: any[] = Array.isArray(body.results) ? body.results : []; const points = rows.reduce((a, r) => a + Number(r.points || 0), 0); const max = rows.length;
      const topics: Record<string, { points: number; max: number }> = {}; for (const r of rows) { const t = topics[r.topic] = topics[r.topic] || { points: 0, max: 0 }; t.points += Number(r.points || 0); t.max += 1; }
      const weakest = Object.entries(topics).sort((a, b) => a[1].points / a[1].max - b[1].points / b[1].max)[0];
      return json({ ok: true, points, max, score: max ? Math.round(points / max * 100) / 100 : 0, topics, recommend: weakest && weakest[1].points / weakest[1].max < 1 ? weakest[0] : null, strong: null, preview: true }); }
    if (action === "history") return json({ ok: true, sessions: [], topics: {}, agent: pAgent, preview: true });
    return json({ error: "Unbekannte Aktion." }, 400);
  }
  const { data: empId } = await user.rpc("get_my_employee_id"); if (!empId) return json({ error: "Kein Mitarbeiter-Datensatz verknüpft." }, 403);
  const { data: emp } = await admin.from("employees").select("id,project_id,first_name").eq("id", empId).maybeSingle();
  if (!emp?.project_id) return json({ error: "Kein Projekt hinterlegt." }, 403);
  const pid = emp.project_id;
  const { data: pa } = await admin.from("partner_agents").select("name").eq("project_id", pid).maybeSingle(); const agentName = pa?.name || "Coach";

  if (action === "start") {
    let s = body.settings || {}; let assignment: any = null;
    if (body.assignment_id) {   // Pflichteinheit: Vorgaben gelten, keine Wahl
      const { data: as } = await admin.from("coach_assignments").select("*").eq("id", body.assignment_id).eq("employee_id", empId).eq("status", "open").maybeSingle();
      if (!as) return json({ error: "Diese Pflichteinheit gibt es nicht mehr oder sie ist schon erledigt." }, 404);
      assignment = as; s = { mode: as.topic ? "topic" : (as.zielgebiet ? "sprint" : "daily"), topic: as.topic, zielgebiet: as.zielgebiet, minutes: as.minutes, difficulty: as.difficulty, kinds: null };
    }
    const minutes = [2, 5, 10, 15].includes(Number(s.minutes)) ? Number(s.minutes) : 5;
    const n = countFor(minutes); const diff = ["leicht", "mittel", "schwer", "mix"].includes(s.difficulty) ? s.difficulty : "mix";
    const kinds: string[] = Array.isArray(s.kinds) && s.kinds.length ? s.kinds.filter((k: string) => ["mc", "gap", "match", "order", "free"].includes(k)) : ["mc", "gap", "match", "order", "free"];
    let q = admin.from("coach_questions").select("*").eq("project_id", pid).eq("status", "active").in("kind", kinds);
    if (diff !== "mix") q = q.eq("difficulty", diff);
    if (s.mode === "topic" && s.topic) q = q.eq("topic", String(s.topic));
    if (s.mode === "sprint" && s.zielgebiet) q = q.or("zielgebiet.ilike.%" + String(s.zielgebiet).replace(/[%,()]/g, "") + "%,prompt.ilike.%" + String(s.zielgebiet).replace(/[%,()]/g, "") + "%");
    const { data: pool } = await q.limit(2000);
    if (!pool || !pool.length) return json({ error: "Dazu gibt es noch keine Übungsfragen." }, 404);
    // Gedächtnis: zuletzt richtig beantwortete Fragen (7 Tage) raus, Themen mit schwachem Schnitt bevorzugen
    const since = new Date(Date.now() - 7 * 864e5).toISOString();
    const { data: recent } = await admin.from("coach_answers").select("question_id,topic,points,max_points").eq("employee_id", empId).gte("answered_at", since);
    const doneRight = new Set((recent || []).filter((r: any) => Number(r.points) >= Number(r.max_points)).map((r: any) => r.question_id));
    const topicScore: Record<string, { p: number; m: number }> = {}; for (const r of (recent || [])) { const t = topicScore[r.topic] = topicScore[r.topic] || { p: 0, m: 0 }; t.p += Number(r.points); t.m += Number(r.max_points); }
    let cand = pool.filter((x: any) => !doneRight.has(x.id)); if (cand.length < n) cand = pool;
    // Gewichtung: je Thema gleich viel Chance (kein Übergewicht großer Themen), schwache Themen doppelt
    const byTopic: Record<string, any[]> = {}; for (const x of cand) (byTopic[x.topic] = byTopic[x.topic] || []).push(x);
    const topics = Object.keys(byTopic); const weight = (t: string) => { const ts = topicScore[t]; return ts && ts.m > 0 && ts.p / ts.m < 0.7 ? 2 : 1; };
    // Freitext höchstens ein Drittel (sonst wird die Einheit zäh), am Ende der Einheit
    const capFree = Math.max(1, Math.floor(n / 3)); const hasNonFree = cand.some((x: any) => x.kind !== "free");
    const picked: any[] = []; const used = new Set<string>(); let freeN = 0, guard = 0;
    while (picked.length < n && used.size < cand.length && guard++ < 5000) {
      const bag = topics.flatMap((t) => Array(weight(t)).fill(t)); const t = bag[Math.floor(Math.random() * bag.length)];
      const opts = byTopic[t].filter((x: any) => !used.has(x.id)); if (!opts.length) continue;
      const x = opts[Math.floor(Math.random() * opts.length)]; used.add(x.id);
      if (x.kind === "free") { if (freeN >= capFree && hasNonFree) continue; freeN++; }
      picked.push(x);
    }
    const list = [...shuffle(picked.filter((x) => x.kind !== "free")), ...picked.filter((x) => x.kind === "free")].slice(0, n);
    const { data: sess, error } = await admin.from("coach_sessions").insert({ employee_id: empId, project_id: pid, user_id: u.user.id, assignment_id: assignment ? assignment.id : null, settings: { mode: s.mode || "daily", topic: s.topic || null, zielgebiet: s.zielgebiet || null, minutes, difficulty: diff, kinds, assignment: assignment ? { id: assignment.id, by: assignment.assigned_by_name, note: assignment.note } : null }, question_ids: list.map((x) => x.id) }).select("id").single();
    if (error) return json({ error: error.message }, 500);
    return json({ ok: true, session_id: sess.id, agent: agentName, assignment: assignment ? { id: assignment.id, topic: assignment.topic, by: assignment.assigned_by_name, note: assignment.note } : null, questions: list.map(publicQ) });
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
    return json({ ok: true, answer_id: ans.id, points: g.points, feedback: g.feedback, rubric: g.rubric || null, solution: q.answer, explanation: q.explanation, source: q.source_label, topic: q.topic });
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
    return json({ ok: true, points, max, score, topics, recommend: weakest && weakest[1].points / weakest[1].max < 1 ? weakest[0] : null, strong: strongest ? strongest[0] : null });
  }

  if (action === "history") {
    const { data: sessions } = await admin.from("coach_sessions").select("id,settings,points,max_points,score,topic_scores,started_at,finished_at,status").eq("employee_id", empId).eq("status", "done").order("finished_at", { ascending: false }).limit(30);
    const since = new Date(Date.now() - 30 * 864e5).toISOString();
    const { data: answers } = await admin.from("coach_answers").select("topic,points,max_points").eq("employee_id", empId).gte("answered_at", since);
    const topics: Record<string, { points: number; max: number }> = {}; for (const r of (answers || [])) { const t = topics[r.topic] = topics[r.topic] || { points: 0, max: 0 }; t.points += Number(r.points); t.max += 1; }
    return json({ ok: true, sessions: sessions || [], topics, agent: agentName });
  }
  return json({ error: "Unbekannte Aktion." }, 400);
});
