// Coach · Schnitt 2: Fragenbank aus dem Wissensspeicher bauen. Service-Role (Cron nachts + auf Anfrage {project_id}).
// Regeln zuerst (deterministisch, richtige Antwort = wörtlich der Register-Wert, Ablenker = echte Nachbarwerte, nie erfunden):
//   mc    Auswahl: Fakt mit Zielgebiet → Ablenker = gleicher Fakt-Typ (topic) anderer Zielgebiete (mittel) oder fremde Themen (leicht);
//         Fakt ohne Zielgebiet → Ablenker = Werte anderer Einträge desselben Themas (mittel)
//   gap   Lücke: kurze Werte (Nummern, Adressen, Fristen) → Eingabe, Vergleich normalisiert
//   match Zuordnung: Thema mit ≥4 Zielgebieten (Agentur, Notfallnummer, Treffpunkt) → 4 Paare
// Dann KI (Claude) nur für Prosa: Situationen (free) mit Bewertungsvorlage aus dem Abschnitt und Reihenfolgen (order)
// aus Ablauf-Abschnitten; jede Vorlage muss WÖRTLICH im Abschnitt stehen, sonst wird die Frage verworfen.
// Fingerprint verhindert Dubletten; 'stale' Fragen (Fakt geändert) werden neu gebaut, 'blocked' bleibt gesperrt.
// Deploy: supabase functions deploy coach-generate --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
const MODEL = "claude-sonnet-5";
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const norm = (s: any) => String(s ?? "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/\s+/g, " ").trim();
const digits = (s: any) => String(s ?? "").replace(/\D+/g, "");
const shuffle = <T,>(a: T[]) => { const b = a.slice(); for (let i = b.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [b[i], b[j]] = [b[j], b[i]]; } return b; };
async function fp(s: string) { const h = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)); return Array.from(new Uint8Array(h)).slice(0, 12).map((b) => b.toString(16).padStart(2, "0")).join(""); }
async function fetchAll(mk: (a: number, b: number) => any): Promise<any[]> { const out: any[] = []; for (let a = 0; ; a += 1000) { const { data, error } = await mk(a, a + 999); if (error) throw error; out.push(...(data || [])); if (!data || data.length < 1000) break; } return out; }

type Q = { kind: string; difficulty: string; topic: string; zielgebiet: string | null; prompt: string; options: any; answer: any; explanation: string; source_kind: string; source_id: string; source_label: string; source_stamp: string | null; gen_by: string; fingerprint?: string };

// ── Regelbasiert aus Fakten ───────────────────────────────────────────────────────────────────────
function ruleQuestions(facts: any[], docTitles: Record<string, string>): Q[] {
  const out: Q[] = [];
  const srcLabel = (f: any) => (f.source === "manual" ? "Register, von Hand gepflegt" : (docTitles[f.source_document_id] || "Register") + (f.source_locator ? ", " + f.source_locator : ""));
  const byTopic: Record<string, any[]> = {};
  for (const f of facts) (byTopic[f.topic] = byTopic[f.topic] || []).push(f);
  const topics = Object.keys(byTopic);
  const qualTxt = (f: any) => { const q = f.qualifier && typeof f.qualifier === "object" ? Object.entries(f.qualifier).filter(([, v]) => v).map(([k, v]) => k + " " + v).join(", ") : ""; return q ? " (" + q + ")" : ""; };
  const labelOf = (f: any) => f.label + qualTxt(f);
  // Ablenker dürfen die richtige Antwort weder enthalten noch in ihr enthalten sein ("Travco" vs "Travco/Touring" wäre beides richtig).
  const distinctByValue = (arr: any[], self: any) => { const me = norm(self.value); const seen = new Set<string>([me]); return arr.filter((x) => { const k = norm(x.value); if (seen.has(k) || k === "" || k.includes(me) || me.includes(k)) return false; seen.add(k); return true; }); };
  // Regelfragen nur aus nachschlagbaren Fakten: mit Zielgebiet, oder Kontakt/Zeit/Preis/Regel mit kurzem Wert. Prosa (Abläufe) übernimmt die KI.
  const NO_TOPIC = /^(stand|aktualit|version|quelle|dokument)/i;   // Dokumentstand ist kein Übungsstoff
  const askable = (f: any) => !!f.value && String(f.value).length <= 120 && !NO_TOPIC.test(String(f.topic || "")) && (f.zielgebiet || ["kontakt", "zeit", "preis", "regel"].includes(f.info_type));

  for (const f of facts) {
    if (!askable(f)) continue;
    const zg = f.zielgebiet || null;
    // mc mittel: Nachbarn gleichen Themas
    const sib = distinctByValue(byTopic[f.topic].filter((x) => x.id !== f.id && askable(x) && (zg ? x.zielgebiet !== zg : true)), f);
    if (sib.length >= 3) {
      const d = shuffle(sib).slice(0, 3);
      const opts = shuffle([f, ...d]).map((x, i) => ({ key: "ABCD"[i], text: String(x.value), _id: x.id }));
      const key = opts.find((o) => o._id === f.id)!.key;
      out.push({ kind: "mc", difficulty: "mittel", topic: f.topic, zielgebiet: zg, prompt: "Was gilt für: " + labelOf(f) + "?", options: opts.map(({ key, text }) => ({ key, text })), answer: { key },
        explanation: labelOf(f) + ": " + f.value, source_kind: "fact", source_id: f.id, source_label: srcLabel(f), source_stamp: f.updated_at, gen_by: "rule" });
    }
    // mc leicht: Ablenker aus fremden Themen (deutlich anders)
    const foreign = distinctByValue(shuffle(topics.filter((t) => t !== f.topic)).slice(0, 6).flatMap((t) => byTopic[t]).filter((x) => askable(x)), f);
    if (foreign.length >= 3) {
      const d = shuffle(foreign).slice(0, 3);
      const opts = shuffle([f, ...d]).map((x, i) => ({ key: "ABCD"[i], text: String(x.value), _id: x.id }));
      const key = opts.find((o) => o._id === f.id)!.key;
      out.push({ kind: "mc", difficulty: "leicht", topic: f.topic, zielgebiet: zg, prompt: "Was gilt für: " + labelOf(f) + "?", options: opts.map(({ key, text }) => ({ key, text })), answer: { key },
        explanation: labelOf(f) + ": " + f.value, source_kind: "fact", source_id: f.id, source_label: srcLabel(f), source_stamp: f.updated_at, gen_by: "rule" });
    }
    // gap: kurze Werte mit Zahl/Adresse → tippen
    const v = String(f.value);
    if (v.length <= 60 && (/\d{3,}/.test(v) || /@/.test(v))) {
      out.push({ kind: "gap", difficulty: digits(v).length >= 8 ? "schwer" : "mittel", topic: f.topic, zielgebiet: zg, prompt: "Wie lautet: " + labelOf(f) + "?", options: null, answer: { accept: [v] },
        explanation: labelOf(f) + ": " + v, source_kind: "fact", source_id: f.id, source_label: srcLabel(f), source_stamp: f.updated_at, gen_by: "rule" });
    }
  }
  // match: Thema mit ≥4 Zielgebieten, je Zielgebiet ein Wert
  for (const t of topics) {
    const rows = byTopic[t].filter((x) => x.zielgebiet && x.value && String(x.value).length <= 80);
    const byZg: Record<string, any> = {}; for (const r of rows) if (!byZg[r.zielgebiet]) byZg[r.zielgebiet] = r;
    const zgs = Object.keys(byZg); if (zgs.length < 4) continue;
    for (let round = 0; round < Math.min(3, Math.floor(zgs.length / 4)); round++) {
      const pick = shuffle(zgs).slice(0, 4).map((z) => byZg[z]);
      const vals = new Set(pick.map((p) => norm(p.value))); if (vals.size < 4) continue;
      const pairs: Record<string, string> = {}; pick.forEach((p) => { pairs[p.zielgebiet] = String(p.value); });
      out.push({ kind: "match", difficulty: "mittel", topic: t, zielgebiet: null, prompt: "Ordne zu: " + t + " je Zielgebiet.", options: { left: pick.map((p) => p.zielgebiet), right: shuffle(pick.map((p) => String(p.value))) }, answer: { pairs },
        explanation: pick.map((p) => p.zielgebiet + ": " + p.value).join(" · "), source_kind: "fact", source_id: pick[0].id, source_label: srcLabel(pick[0]), source_stamp: pick[0].updated_at, gen_by: "rule" });
    }
  }
  return out;
}

// ── KI aus Prosa (Situationen, Reihenfolgen) ─────────────────────────────────────────────────────
const TOOL = { name: "fragen", description: "Übungsfragen aus dem Abschnitt", input_schema: { type: "object", properties: { fragen: { type: "array", items: { type: "object", properties: {
  kind: { type: "string", enum: ["free", "order"] },
  prompt: { type: "string", description: "free: konkrete Situation am Telefon (Kunde sagt …) mit Frage 'Was sagst/tust du?'; order: 'Bringe die Schritte in die richtige Reihenfolge: …'" },
  must: { type: "array", items: { type: "string" }, description: "free: 2-4 Kernpunkte, die in einer guten Antwort vorkommen müssen, WÖRTLICH aus dem Abschnitt (kurze Phrasen)" },
  nice: { type: "array", items: { type: "string" }, description: "free: 0-2 Zusatzpunkte, wörtlich aus dem Abschnitt" },
  steps: { type: "array", items: { type: "string" }, description: "order: 3-6 Schritte in der RICHTIGEN Reihenfolge, wörtlich/knapp aus dem Abschnitt" },
  explanation: { type: "string", description: "1-2 Sätze Auflösung aus dem Abschnitt" },
  difficulty: { type: "string", enum: ["mittel", "schwer"] },
}, required: ["kind", "prompt", "explanation", "difficulty"] } } }, required: ["fragen"] } };

async function aiQuestions(chunk: any, docTitle: string): Promise<Q[]> {
  if (!ANTHROPIC_KEY) return [];
  const system = "Du baust Übungsfragen für Call-Center-Mitarbeiter aus EINEM Abschnitt einer Schulungsunterlage. Nur, was wörtlich im Abschnitt steht. " +
    "Keine Platzhalter, keine Beispielwerte (Beispiel-Buchungsnummern, Musterdaten) als Antwort und auch keine erfundenen Nummern, Namen oder Daten in der Situation selbst (schreibe 'ein Kunde', nicht 'Kunde mit Vorgangsnummer 234567'). Wenn der Abschnitt keine brauchbare Situation oder keinen Ablauf hergibt, gib eine leere Liste. " +
    "free = Situation, in die die Kollegin am Telefon gerät, mit der Frage, was sie sagt oder tut; must = die Kernpunkte wörtlich aus dem Abschnitt. order = ein echter Ablauf mit klarer Reihenfolge. Höchstens 3 Fragen. Duze.";
  const resp = await fetch("https://api.anthropic.com/v1/messages", { method: "POST", headers: { "x-api-key": ANTHROPIC_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({ model: MODEL, max_tokens: 1800, system, tools: [TOOL], tool_choice: { type: "tool", name: "fragen" }, messages: [{ role: "user", content: "ABSCHNITT [" + (chunk.section || docTitle) + "]:\n" + String(chunk.content || "") }] }) });
  const data = await resp.json(); if (!resp.ok) throw new Error(data?.error?.message || String(resp.status));
  const tool = (data.content || []).find((c: any) => c.type === "tool_use"); const list = (tool?.input?.fragen || []) as any[];
  const body = norm(chunk.content);
  const inText = (s: string) => { const w = norm(s).split(" ").filter((x) => x.length >= 4); if (!w.length) return false; const hit = w.filter((x) => body.includes(x)).length; return hit / w.length >= 0.6; };
  const out: Q[] = [];
  for (const q of list) {
    if (!q || !q.prompt) continue;
    const src = { source_kind: "chunk", source_id: chunk.id, source_label: docTitle + (chunk.section ? " / " + chunk.section : "") + (chunk.page ? ", S. " + chunk.page : ""), source_stamp: chunk.created_at, gen_by: "ai" };
    if (q.kind === "free") {
      const must = (q.must || []).filter((m: string) => m && inText(m)).slice(0, 4); if (must.length < 2) continue;   // Vorlage muss aus dem Text stammen
      const nice = (q.nice || []).filter((m: string) => m && inText(m)).slice(0, 2);
      out.push({ kind: "free", difficulty: "schwer", topic: chunk.section || "Schulungsunterlage", zielgebiet: null, prompt: q.prompt, options: null, answer: { must, nice }, explanation: q.explanation || "", ...src });
    } else if (q.kind === "order") {
      const steps = (q.steps || []).filter((s: string) => s && inText(s)); if (steps.length < 3 || steps.length > 6 || steps.length !== (q.steps || []).length) continue;
      out.push({ kind: "order", difficulty: q.difficulty === "mittel" ? "mittel" : "schwer", topic: chunk.section || "Schulungsunterlage", zielgebiet: null, prompt: q.prompt, options: shuffle(steps), answer: { sequence: steps }, explanation: q.explanation || "", ...src });
    }
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* Cron */ }
  const onlyProject = typeof body.project_id === "string" ? body.project_id : null;
  const aiLimit = Number.isFinite(body.ai_limit) ? Number(body.ai_limit) : 30;   // KI-Abschnitte je Lauf und Partner (Kosten)
  const projects = onlyProject ? [onlyProject] : [...new Set((await fetchAll((a, b) => sb.from("kb_facts").select("project_id").eq("status", "active").range(a, b))).map((r: any) => r.project_id))];
  const report: any[] = [];
  for (const pid of projects) {
    const facts = await fetchAll((a, b) => sb.from("kb_facts").select("id,topic,zielgebiet,info_type,label,value,qualifier,source,source_document_id,source_locator,updated_at").eq("project_id", pid).eq("status", "active").range(a, b));
    const { data: docs } = await sb.from("kb_documents").select("id,title,doc_kind").eq("project_id", pid);
    const docTitles: Record<string, string> = {}; for (const d of (docs || [])) docTitles[d.id] = d.title;
    const existing = await fetchAll((a, b) => sb.from("coach_questions").select("id,fingerprint,status,source_kind,source_id").eq("project_id", pid).range(a, b));
    const have = new Map(existing.map((e: any) => [e.fingerprint, e]));
    let rule = ruleQuestions(facts, docTitles);
    // KI: Abschnitte der Schulungs-/Ablauf-Dokumente ohne aktive Fragen
    const aiDocIds = (docs || []).filter((d) => ["coaching", "ablauf", "faq"].includes(d.doc_kind)).map((d) => d.id);
    let ai: Q[] = []; let aiErrors = 0;
    if (aiDocIds.length && aiLimit > 0) {
      const chunks = await fetchAll((a, b) => sb.from("kb_chunks").select("id,document_id,section,page,content,created_at").eq("project_id", pid).in("document_id", aiDocIds).range(a, b));
      const covered = new Set(existing.filter((e: any) => e.source_kind === "chunk" && e.status !== "stale").map((e: any) => e.source_id));
      const todo = shuffle(chunks.filter((c: any) => !covered.has(c.id) && String(c.content || "").length >= 250)).slice(0, aiLimit);
      const results = await Promise.all(todo.map((c: any) => aiQuestions(c, docTitles[c.document_id] || "Unterlage").catch(() => { aiErrors++; return [] as Q[]; })));
      ai = results.flat();
      // Abschnitte ohne brauchbare Frage: Merkposten, damit sie nicht jede Nacht neu bezahlt werden
      for (const c of todo) if (!results[todo.indexOf(c)].length) await sb.from("coach_questions").insert({ project_id: pid, kind: "free", difficulty: "mittel", topic: c.section || "-", prompt: "-", answer: {}, explanation: null, source_kind: "chunk", source_id: c.id, source_label: "(kein Stoff)", status: "blocked", gen_by: "ai", fingerprint: await fp("none:" + c.id) }).then(() => {}, () => {});
    }
    let inserted = 0, reactivated = 0, skipped = 0;
    for (const q of [...rule, ...ai]) {
      q.fingerprint = await fp(q.kind + "|" + q.source_id + "|" + q.difficulty + "|" + norm(q.prompt) + "|" + norm(JSON.stringify(q.answer)));
      const ex = have.get(q.fingerprint);
      if (ex) { if (ex.status === "stale") { await sb.from("coach_questions").update({ status: "active", options: q.options, answer: q.answer, explanation: q.explanation, source_stamp: q.source_stamp, updated_at: new Date().toISOString() }).eq("id", ex.id); reactivated++; } else skipped++; continue; }
      const { error } = await sb.from("coach_questions").insert({ project_id: pid, ...q }); if (!error) inserted++;
    }
    // Veraltete Fragen, für die es keinen Ersatz gab (Fakt weg): bleiben stale (nicht spielbar)
    const { count: active } = await sb.from("coach_questions").select("id", { count: "exact", head: true }).eq("project_id", pid).eq("status", "active");
    report.push({ project_id: pid, facts: facts.length, rule: rule.length, ai: ai.length, ai_errors: aiErrors, inserted, reactivated, skipped, active });
  }
  return json({ ok: true, report });
});
