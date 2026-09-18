// Schulung per Link (öffentlich, ohne Login). Zugang = Link-Token der Schulung + Mitarbeiter-PIN (time_pins) oder Gast-PIN.
// Lösungen verlassen den Server nie vor der Antwort. Der Durchlauf (training_runs) ist die Sitzung: run_id = zufällige UUID.
// Nach der PIN wählt die Person: zugewiesene Schulung des Links, „Überrasch mich“ (zufällig quer durch die Themen) oder ein Thema.
// Der Link bleibt dauerhaft nutzbar. Fragen für Zufall/Thema kommen aus der geprüften Fragenbank mit Miriams Ebenen (layers).
// Aktionen: get {token} · login {token, pin} · menu {run} · choose {run, mode, topic} · start {run} · question {run} · answer {run, answer} · finish {run} · result {run}
// Deploy: supabase functions deploy training-run --use-api --no-verify-jwt
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { publicQ, gradeAny, claudeTool, shuffle, norm } from "../_shared/coach_grade.ts";

const SB_URL = Deno.env.get("SUPABASE_URL")!, SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, s = 200) => { if (s >= 400) console.error("[training-run] " + s + " " + JSON.stringify(b)); return new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } }); };
const admin = createClient(SB_URL, SERVICE);
const UUID = /^[0-9a-f-]{36}$/i;

async function agentInfo(key: string) { const { data } = await admin.from("ai_agents").select("key,name,accent,avatar_url,tagline,disclosure").eq("key", key || "miriam").maybeSingle(); return data || { key: "miriam", name: "Miriam", accent: "#b45309", avatar_url: null, tagline: "", disclosure: "" }; }
async function loadTraining(token: string) { if (!token || token.length < 12) return null; const { data } = await admin.from("trainings").select("*").eq("token", token).maybeSingle(); return data; }
const live = (t: any) => t && t.status === "live" && (!t.expires_at || new Date(t.expires_at).getTime() > Date.now());
const pubT = (t: any, ag: any) => ({ id: t.id, title: t.title, intro: t.intro, topics: t.topics || [], n: (t.questions || []).length, minutes: t.minutes_est, kinds: [...new Set((t.questions || []).map((q: any) => q.kind))], agent: { name: ag.name, accent: ag.accent, avatar_url: ag.avatar_url, disclosure: ag.disclosure } });
async function loadRun(id: string) { if (!UUID.test(id || "")) return null; const { data } = await admin.from("training_runs").select("*").eq("id", id).maybeSingle(); return data; }
const secs = (a: string, b: string) => Math.max(0, Math.round((new Date(b).getTime() - new Date(a).getTime()) / 1000));

const UNIT_N = 8;   // Fragen je Zufalls- oder Themen-Einheit
async function bankFor(pid: string) { const { data } = await admin.from("coach_questions").select("*").eq("project_id", pid).eq("status", "active").gte("quality", 4).not("layers", "is", null).limit(3000); return (data || []).filter((q: any) => !(q.layers && q.layers.empty)); }
async function menuFor(t: any, employeeId: string | null, guestId: string | null) {
  const bank = await bankFor(t.project_id); const topics: Record<string, number> = {}; for (const q of bank) topics[q.topic] = (topics[q.topic] || 0) + 1;
  let hq = admin.from("training_runs").select("mode,topic,score,seconds,finished_at").eq("training_id", t.id).eq("status", "done").order("finished_at", { ascending: false }).limit(12);
  hq = employeeId ? hq.eq("employee_id", employeeId) : hq.eq("guest_id", guestId);
  const { data: hist } = await hq;
  return { assigned: { title: t.title, n: (t.questions || []).length, minutes: t.minutes_est, topics: t.topics || [] }, random_n: Math.min(UNIT_N, bank.length), bank_n: bank.length,
    topics: Object.keys(topics).sort((a, b) => a.localeCompare(b, "de")).map((k) => ({ t: k, n: topics[k] })), history: hist || [] };
}
// Zufall: reihum über alle Themen; Thema: nur dieses Thema; ähnliche Situationen nur einmal; Freitext ≤ Hälfte, ans Ende
function pickUnit(bank: any[], topic: string | null, n: number) {
  const rows = shuffle(bank.filter((q) => !topic || q.topic === topic));
  const groups = new Map<string, any[]>(); for (const r of rows) (groups.get(r.topic) || groups.set(r.topic, []).get(r.topic))!.push(r);
  const order = shuffle([...groups.keys()]); const capFree = Math.max(1, Math.ceil(n / 2));
  const bag = (x: any) => new Set(norm(x.prompt).replace(norm(x.zielgebiet || "zzz"), "").split(" ").filter((w: string) => w.length >= 4));
  const similar = (a: Set<string>, b: Set<string>) => { let hit = 0; for (const w of a) if (b.has(w)) hit++; return hit / Math.max(1, Math.min(a.size, b.size)) >= 0.6; };
  const picked: any[] = []; const bags: Set<string>[] = []; let freeN = 0;
  for (let k = 0; picked.length < n; k++) { let any = false; for (const t of order) { const x = (groups.get(t) || [])[k]; if (!x) continue; any = true; if (picked.length >= n) break; const bg = bag(x); if (bags.some((b) => similar(b, bg))) continue; if (x.kind === "free") { if (freeN >= capFree) continue; freeN++; } bags.push(bg); picked.push(x); } if (!any) break; }
  const list = [...shuffle(picked.filter((x) => x.kind !== "free")), ...picked.filter((x) => x.kind === "free")];
  return list.map((x) => ({ id: x.id, kind: x.kind, difficulty: x.difficulty, topic: x.topic, zielgebiet: x.zielgebiet, prompt: x.prompt, options: x.options, answer: x.answer, explanation: x.explanation, source_label: x.source_label, why: x.layers?.why || null, objection: x.layers?.objection || null, apply: x.layers?.apply || null }));
}
const SUM_TOOL = { name: "rueckmeldung", input_schema: { type: "object", properties: {
  summary: { type: "string", description: "Rückmeldung an die Person: 4-6 kurze Sätze. Was saß, was gefehlt hat (konkret benennen), ein Rat fürs nächste Kundengespräch. Duzen, ehrlich, warm, ohne Floskeln, keine Gedankenstriche." },
  strengths: { type: "array", items: { type: "string" }, description: "2-3 Stärken in Stichworten" },
  gaps: { type: "array", items: { type: "string" }, description: "1-3 Lücken in Stichworten (Thema oder Regel), leer wenn alles saß" },
}, required: ["summary", "strengths", "gaps"] } };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: any = {}; try { body = await req.json(); } catch (_e) { return json({ error: "Ungültige Anfrage." }, 400); }
  const action = String(body.action || "");

  if (action === "get") {
    const t = await loadTraining(String(body.token || "")); if (!t) return json({ error: "Diese Schulung gibt es nicht." }, 404);
    if (!live(t)) return json({ error: t.status === "draft" ? "Diese Schulung ist noch nicht freigegeben." : "Dieser Link ist abgelaufen." }, 410);
    return json({ ok: true, training: pubT(t, await agentInfo(t.agent_key)) });
  }
  if (action === "login") {
    const t = await loadTraining(String(body.token || "")); if (!t || !live(t)) return json({ error: "Dieser Link ist nicht mehr gültig." }, 410);
    const pin = String(body.pin || "").trim(); if (!/^\d{3,8}$/.test(pin)) return json({ error: "Bitte deine PIN eingeben." }, 400);
    const { data: chk, error } = await admin.rpc("training_pin_check", { p_code: pin }); if (error) return json({ error: "PIN-Prüfung fehlgeschlagen." }, 500);
    if (!chk || chk.error) return json({ error: chk?.error === "locked" ? "Zu viele Fehlversuche. Bitte in " + Math.ceil((chk.retry_after_seconds || 300) / 60) + " Minuten noch einmal." : "Diese PIN kennen wir nicht." }, 403);
    // laufenden Durchlauf derselben Person fortsetzen (Seite neu geladen), sonst neuer Durchlauf im Zustand „wählt“
    let rq = admin.from("training_runs").select("*").eq("training_id", t.id).in("status", ["running", "pending"]).gte("started_at", new Date(Date.now() - 6 * 3600e3).toISOString());
    rq = chk.employee_id ? rq.eq("employee_id", chk.employee_id) : rq.eq("guest_id", chk.guest_id);
    const { data: open } = await rq.order("started_at", { ascending: false }).limit(1);
    let run = open && open[0];
    if (!run) { const { data: ins, error: ie } = await admin.from("training_runs").insert({ training_id: t.id, employee_id: chk.employee_id || null, guest_id: chk.guest_id || null, name: chk.name, max: 0, status: "pending" }).select("*").single(); if (ie) return json({ error: ie.message }, 500); run = ins; }
    const { count } = await admin.from("training_runs").select("id", { count: "exact", head: true }).eq("training_id", t.id).eq("status", "done").eq(chk.employee_id ? "employee_id" : "guest_id", chk.employee_id || chk.guest_id);
    return json({ ok: true, run: run.id, name: chk.name, first_name: String(chk.name || "").split(" ")[0], status: run.status, mode: run.mode, answered: (run.answers || []).length, started: !!run.splits?.started, done_before: count || 0, menu: await menuFor(t, chk.employee_id || null, chk.guest_id || null) });
  }

  const run = await loadRun(String(body.run || "")); if (!run) return json({ error: "Durchlauf nicht gefunden." }, 404);
  const { data: t } = await admin.from("trainings").select("*").eq("id", run.training_id).maybeSingle(); if (!t) return json({ error: "Schulung nicht gefunden." }, 404);
  const qs: any[] = (run.mode !== "assigned" && Array.isArray(run.run_questions)) ? run.run_questions : (t.questions || []); const ag = await agentInfo(t.agent_key);
  const unitTitle = run.mode === "random" ? "Überraschung: quer durch die Themen" : run.mode === "topic" ? (run.topic || "Thema") : t.title;

  if (action === "abandon") {   // Einheit abbrechen: bleibt als abgebrochen liegen, neuer Durchlauf zur Wahl
    if (run.status === "running" || run.status === "pending") await admin.from("training_runs").update({ status: "abandoned", updated_at: new Date().toISOString() }).eq("id", run.id);
    const { data: ins, error: ie } = await admin.from("training_runs").insert({ training_id: t.id, employee_id: run.employee_id, guest_id: run.guest_id, name: run.name, max: 0, status: "pending" }).select("*").single(); if (ie) return json({ error: ie.message }, 500);
    return json({ ok: true, run: ins.id, status: "pending", menu: await menuFor(t, run.employee_id, run.guest_id) });
  }
  if (action === "again") {   // Noch eine: neuer Durchlauf derselben Person, zurück zur Wahl
    const { data: ins, error: ie } = await admin.from("training_runs").insert({ training_id: t.id, employee_id: run.employee_id, guest_id: run.guest_id, name: run.name, max: 0, status: "pending" }).select("*").single(); if (ie) return json({ error: ie.message }, 500);
    return json({ ok: true, run: ins.id, status: "pending", menu: await menuFor(t, run.employee_id, run.guest_id) });
  }
  if (action === "menu") return json({ ok: true, status: run.status, mode: run.mode, answered: (run.answers || []).length, menu: await menuFor(t, run.employee_id, run.guest_id) });
  if (action === "choose") {
    if (run.status !== "pending") return json({ error: "Dieser Durchlauf läuft schon." }, 409);
    const mode = ["assigned", "random", "topic"].includes(body.mode) ? body.mode : "assigned"; let list: any[] = []; let topic: string | null = null;
    if (mode === "assigned") list = t.questions || []; else { const bank = await bankFor(t.project_id); topic = mode === "topic" ? String(body.topic || "") : null; if (mode === "topic" && !bank.some((q) => q.topic === topic)) return json({ error: "Zu diesem Thema gibt es noch keine Fragen." }, 404); list = pickUnit(bank, topic, UNIT_N); }
    if (!list.length) return json({ error: "Keine Fragen gefunden." }, 404);
    await admin.from("training_runs").update({ mode, topic, run_questions: mode === "assigned" ? null : list, max: list.length, status: "running", updated_at: new Date().toISOString() }).eq("id", run.id);
    const title = mode === "random" ? "Überraschung: quer durch die Themen" : mode === "topic" ? topic : t.title;
    const intro = mode === "assigned" ? t.intro : mode === "random" ? list.length + " Fragen quer durch alle Themen, jedes Mal anders." : list.length + " Fragen zum Thema „" + topic + "“.";
    return json({ ok: true, unit: { title, intro, n: list.length, minutes: mode === "assigned" ? t.minutes_est : Math.max(3, Math.round(list.length * 1.5)), topics: mode === "assigned" ? (t.topics || []) : [...new Set(list.map((x: any) => x.topic))], kinds: [...new Set(list.map((x: any) => x.kind))], mode } });
  }

  if (action === "start") {   // Stoppuhr läuft ab hier (Server-Zeit)
    if (run.status === "pending") return json({ error: "Bitte zuerst eine Schulung wählen." }, 409);
    if (!run.splits?.started) { const started = new Date().toISOString(); await admin.from("training_runs").update({ started_at: started, splits: { started, last: started, items: [] }, updated_at: started }).eq("id", run.id); }
    return json({ ok: true, i: (run.answers || []).length, n: qs.length });
  }
  if (action === "question") {
    if (run.status !== "running") return json({ ok: true, finished: true });
    const i = (run.answers || []).length; if (i >= qs.length) return json({ ok: true, finished: true, i, n: qs.length });
    return json({ ok: true, i, n: qs.length, question: publicQ(qs[i]) });
  }
  if (action === "answer") {
    if (run.status !== "running") return json({ error: "Dieser Durchlauf ist abgeschlossen." }, 409);
    const i = (run.answers || []).length; const q = qs[i]; if (!q) return json({ error: "Keine offene Frage." }, 409);
    let g: any; try { g = await gradeAny(q, body.answer || {}, ag.name); } catch (e) { return json({ error: "Bewertung fehlgeschlagen: " + (e as Error).message }, 502); }
    const now = new Date().toISOString(); const sp = run.splits || { started: run.started_at, last: run.started_at, items: [] }; const sec = secs(sp.last || run.started_at, now);
    sp.items = [...(sp.items || []), sec]; sp.last = now;
    const answers = [...(run.answers || []), { i, id: q.id, kind: q.kind, topic: q.topic, answer: body.answer || {}, points: g.points, feedback: g.feedback, seconds: sec, at: now }];
    const points = answers.reduce((a, x) => a + Number(x.points || 0), 0);
    await admin.from("training_runs").update({ answers, splits: sp, points, updated_at: now }).eq("id", run.id);
    return json({ ok: true, i, n: qs.length, points: g.points, feedback: g.feedback, rubric: g.rubric || null, solution: q.answer, options_why: q.kind === "mc" ? q.options : null, explanation: q.explanation,
      why: q.why || null, objection: q.objection || null, apply: q.apply || null, source: q.source_label, seconds: sec, total_points: points });
  }
  if (action === "finish" || action === "result") {
    if (run.status === "done" || action === "result") { if (run.status !== "done") return json({ error: "Noch nicht abgeschlossen." }, 409);
      return json({ ok: true, result: { name: run.name, points: run.points, max: run.max, score: run.score, seconds: run.seconds, splits: (run.splits?.items || []), answers: (run.answers || []).map((a: any) => ({ i: a.i, topic: a.topic, kind: a.kind, points: a.points, seconds: a.seconds })), summary: run.summary, strengths: run.splits?.strengths || [], gaps: run.splits?.gaps || [], agent: { name: ag.name, accent: ag.accent, avatar_url: ag.avatar_url }, title: unitTitle, mode: run.mode } }); }
    const answers: any[] = run.answers || []; if (!answers.length) return json({ error: "Noch keine Antwort." }, 409);
    const now = new Date().toISOString(); const seconds = secs(run.started_at, now); const points = answers.reduce((a, x) => a + Number(x.points || 0), 0); const max = qs.length; const score = max ? Math.round(points / max * 100) / 100 : 0;
    // Miriams Rückmeldung: aus den Antworten, den Auflösungen und den Themen
    let summary = "", strengths: string[] = [], gaps: string[] = [];
    try {
      const lines = answers.map((a) => { const q = qs[a.i] || {}; return (a.i + 1) + ". [" + q.topic + "] " + q.prompt + "\n   Antwort: " + JSON.stringify(a.answer).slice(0, 300) + "\n   Punkte: " + Math.round(Number(a.points) * 100) + " %" + (a.feedback ? " · Bewertung: " + a.feedback : "") + " · " + a.seconds + " s"; }).join("\n");
      const r = await claudeTool("Du bist " + ag.name + ", KI-Trainerin von TIVE 360°. Du gibst am Ende einer Schulung die Rückmeldung. Ehrlich und warm, konkret, duzen, keine Floskeln, keine Gedankenstriche. Beziehe dich nur auf die Fragen und Antworten unten, erfinde nichts.",
        "Schulung: " + unitTitle + "\nTeilnehmer: " + run.name.split(" ")[0] + "\nErgebnis: " + Math.round(score * 100) + " % (" + points + " von " + max + ") in " + Math.round(seconds / 60) + " Minuten\n\n" + lines, SUM_TOOL, 900);
      summary = String(r.summary || ""); strengths = (r.strengths || []).slice(0, 3); gaps = (r.gaps || []).slice(0, 3);
    } catch (_e) { summary = ""; }
    const sp = run.splits || {}; sp.strengths = strengths; sp.gaps = gaps;
    await admin.from("training_runs").update({ status: "done", finished_at: now, seconds, points, max, score, summary, splits: sp, updated_at: now }).eq("id", run.id);
    return json({ ok: true, result: { name: run.name, points, max, score, seconds, splits: sp.items || [], answers: answers.map((a) => ({ i: a.i, topic: a.topic, kind: a.kind, points: a.points, seconds: a.seconds })), summary, strengths, gaps, agent: { name: ag.name, accent: ag.accent, avatar_url: ag.avatar_url }, title: unitTitle, mode: run.mode } });
  }
  return json({ error: "Unbekannte Aktion." }, 400);
});
