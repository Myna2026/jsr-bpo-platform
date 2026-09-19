// Coach · Fragenbank v2. Lieber 500 gute als 1900 mittelmäßige (User). Grundsätze:
//   1. Fragen werden von etwas erzeugt, das den Sinn versteht (Claude), aus dem Wissensspeicher, und danach von einem
//      zweiten Lauf GEPRÜFT (Note 1..5, nur >= 4 wird aktiv). Regeln nur noch da, wo sie taugen: Nummern/Adressen tippen,
//      Zuordnung je Zielgebiet.
//   2. Situationen statt Faktenabfrage: Auswahlfragen sind in eine Lage am Telefon eingebettet („Ein Kunde auf Kos …“),
//      Prosa-Wissen (Regeln, Abläufe) wird zu Situationen mit Bewertungsvorlage und Musterantwort, nie zu Auswahlfragen.
//   3. Nichts erfinden: die richtige Antwort ist WÖRTLICH der Register-Wert; Ablenker sind ausschließlich echte
//      Nachbarwerte (andere Insel, andere Frist) und tragen ein „warum falsch“ (Herkunft), damit die Rückmeldung
//      erklären kann statt nur „falsch“ zu sagen. leicht = 3 nahe Optionen, mittel = 4.
//   4. Deckel je Thema und Art (coach_settings.topic_cap), damit große Themen nicht dominieren.
// Fingerprint: kind + Quelle + Version → einmal erzeugt, nie doppelt bezahlt. Cron nachts, manuell {project_id, ai_limit, judge}.
// Deploy: supabase functions deploy coach-generate --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
const MODEL = "claude-sonnet-5";
const GEN_VERSION = 2;
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const norm = (s: any) => String(s ?? "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/\s+/g, " ").trim();
const digits = (s: any) => String(s ?? "").replace(/\D+/g, "");
const shuffle = <T,>(a: T[]) => { const b = a.slice(); for (let i = b.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [b[i], b[j]] = [b[j], b[i]]; } return b; };
async function fp(s: string) { const h = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)); return Array.from(new Uint8Array(h)).slice(0, 12).map((b) => b.toString(16).padStart(2, "0")).join(""); }
async function fetchAll(mk: (a: number, b: number) => any): Promise<any[]> { const out: any[] = []; for (let a = 0; ; a += 1000) { const { data, error } = await mk(a, a + 999); if (error) throw error; out.push(...(data || [])); if (!data || data.length < 1000) break; } return out; }
const NO_TOPIC = /^(stand|aktualit|version|quelle|dokument)/i;
const overlap = (phrase: string, text: string) => { const w = norm(phrase).split(" ").filter((x) => x.length >= 4); if (!w.length) return false; const t = norm(text); return w.filter((x) => t.includes(x)).length / w.length >= 0.6; };

async function claude(system: string, user: string, tool: any, maxTokens = 2500): Promise<any> {
  const resp = await fetch("https://api.anthropic.com/v1/messages", { method: "POST", headers: { "x-api-key": ANTHROPIC_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({ model: MODEL, max_tokens: maxTokens, system, tools: [tool], tool_choice: { type: "tool", name: tool.name }, messages: [{ role: "user", content: user }] }) });
  const data = await resp.json(); if (!resp.ok) throw new Error(data?.error?.message || String(resp.status));
  return (data.content || []).find((c: any) => c.type === "tool_use")?.input || {};
}
async function pmap<T, R>(items: T[], n: number, f: (t: T) => Promise<R>): Promise<R[]> { const out: R[] = new Array(items.length); let i = 0; await Promise.all(Array(Math.min(n, items.length)).fill(0).map(async () => { while (i < items.length) { const k = i++; try { out[k] = await f(items[k]); } catch (e) { out[k] = (e as any); } } })); return out; }

type Q = { kind: string; difficulty: string; topic: string; zielgebiet: string | null; prompt: string; options: any; answer: any; explanation: string; source_kind: string; source_id: string; source_label: string; source_stamp: string | null; gen_by: string; fingerprint?: string; quality?: number | null; judge_note?: string | null };
const srcLabel = (f: any, docTitles: Record<string, string>) => (f.source === "manual" ? "Register, von Hand gepflegt" : (docTitles[f.source_document_id] || "Register") + (f.source_locator ? ", " + f.source_locator : ""));
const lbl = (f: any) => { const q = f.qualifier && typeof f.qualifier === "object" ? Object.entries(f.qualifier).filter(([, v]) => v).map(([k, v]) => k + " " + v).join(", ") : ""; return f.label + (q ? " (" + q + ")" : ""); };
const isFactish = (f: any) => !!f.value && !NO_TOPIC.test(String(f.topic || "")) && String(f.value).length <= 120 && (f.zielgebiet || ["kontakt", "zeit", "preis", "regel"].includes(f.info_type));
const isProse = (f: any) => !!f.value && !NO_TOPIC.test(String(f.topic || "")) && !isFactish(f) && String(f.value).length >= 40;

// Tipp-Frage nur als echte Situation: eine Nummer, die man dem Kunden am Telefon durchgibt (Notfall/Agentur vor Ort je Zielgebiet).
// Interne Kontakte, Supplier-Adressen und Coaching-Felder sind KEINE Tippfragen (User: „Das ist keine Frage, das ist ein Datenbankfeld“).
const gapWorthy = (f: any, v: string) => !!f.zielgebiet && /\d{6,}/.test(v.replace(/\s/g, "")) && /notfall|agentur vor ort|hotline|notruf/i.test(String(f.label || "") + " " + String(f.topic || ""));
const gapPrompt = (f: any) => "Ein Kunde ruft aus " + String(f.zielgebiet).split(" / ").pop() + " an, es ist dringend, und er braucht sofort die Nummer der Agentur vor Ort. Welche Nummer gibst du ihm durch?";
// ── Regeln: Tippen (Nummern/Adressen) + Zuordnung ───────────────────────────────────────────────────
function ruleQuestions(facts: any[], docTitles: Record<string, string>): Q[] {
  const out: Q[] = []; const byTopic: Record<string, any[]> = {}; for (const f of facts) (byTopic[f.topic] = byTopic[f.topic] || []).push(f);
  for (const f of facts) {
    const v = String(f.value || ""); if (!isFactish(f) || v.length > 40 || !gapWorthy(f, v)) continue;
    out.push({ kind: "gap", difficulty: digits(v).length >= 8 ? "schwer" : "mittel", topic: f.topic, zielgebiet: f.zielgebiet || null, prompt: gapPrompt(f), options: null, answer: { accept: [v] },
      explanation: lbl(f) + ": " + v, source_kind: "fact", source_id: f.id, source_label: srcLabel(f, docTitles), source_stamp: f.updated_at, gen_by: "rule" });
  }
  // Zuordnung: nur Nummern, die man dem Kunden durchgibt (Notfall/Agentur vor Ort). Ein Trainer würde sagen: „Vier Kunden rufen
  // gleichzeitig an …“. Ortsnamen kurz (letzter Teil von „Griechenland / Kos“), jede Nummer nur einmal im Satz.
  const shortZg = (z: string) => String(z || "").split(" / ").pop()!.trim();
  for (const t of Object.keys(byTopic)) {
    if (NO_TOPIC.test(t)) continue;
    const rows = byTopic[t].filter((x) => x.zielgebiet && x.value && gapWorthy(x, String(x.value)));
    const byZg: Record<string, any> = {}; for (const r of rows) { const k = shortZg(r.zielgebiet); if (!byZg[k]) byZg[k] = r; }
    const zgs = Object.keys(byZg); if (zgs.length < 4) continue;
    for (let round = 0; round < Math.min(4, Math.floor(zgs.length / 4)); round++) {
      const pick: any[] = []; const seenV = new Set<string>(); for (const z of shuffle(zgs)) { const r = byZg[z]; const v = digits(r.value); if (seenV.has(v)) continue; seenV.add(v); pick.push(r); if (pick.length === 4) break; }
      if (pick.length < 4) continue;
      const names = pick.map((p) => shortZg(p.zielgebiet)); const pairs: Record<string, string> = {}; pick.forEach((p) => { pairs[shortZg(p.zielgebiet)] = String(p.value); });
      out.push({ kind: "match", difficulty: "mittel", topic: t, zielgebiet: null, prompt: "Vier Kunden rufen gleichzeitig an, aus " + names.slice(0, 3).join(", ") + " und " + names[3] + ". Alle brauchen sofort die Nummer der Agentur vor Ort. Welche Nummer gehört zu welchem Ort?", options: { left: names, right: shuffle(pick.map((p) => String(p.value))) }, answer: { pairs },
        explanation: names.map((n, i) => n + ": " + pick[i].value).join(" · "), source_kind: "fact", source_id: pick[0].id, source_label: srcLabel(pick[0], docTitles), source_stamp: pick[0].updated_at, gen_by: "rule" });
    }
  }
  return out;
}

const JUDGE_TOOL = { name: "pruefung", input_schema: { type: "object", properties: { noten: { type: "array", items: { type: "object", properties: {
  n: { type: "integer" }, score: { type: "integer", minimum: 1, maximum: 5, description: "5 = klar, eindeutig, realistisch am Telefon, Antwortmöglichkeiten sinnvoll; 3 = holprig oder trivial; 1 = unsinnig, mehrdeutig, Platzhalter, mehrere richtige Antworten" },
  note: { type: "string", description: "1 Satz Begründung" } }, required: ["n", "score"] } } }, required: ["noten"] } };
async function judge(qs: Q[]): Promise<void> {
  if (!ANTHROPIC_KEY || !qs.length) return;
  const txt = qs.map((q, i) => "FRAGE " + (i + 1) + " [" + q.kind + " · " + q.difficulty + " · " + q.topic + "]\n" + q.prompt + "\n" +
    (q.kind === "mc" ? (q.options || []).map((o: any) => "  " + o.key + (o.key === q.answer.key ? " (richtig)" : "") + ": " + o.text).join("\n") :
     q.kind === "gap" ? "  erwartet: " + (q.answer.accept || []).join(" | ") :
     q.kind === "match" ? "  Paare: " + JSON.stringify(q.answer.pairs) :
     q.kind === "order" ? "  Reihenfolge: " + (q.answer.sequence || []).join(" → ") :
     "  Kernpunkte: " + (q.answer.must || []).join(" | ") + (q.answer.model_answer ? "\n  Musterantwort: " + q.answer.model_answer : ""))).join("\n\n");
  const system = "Du prüfst Übungsfragen für Call-Center-Kräfte eines Reiseveranstalters, streng und ehrlich. Bewerte jede Frage 1 bis 5.\n" +
    "Für Auswahl (mc), Situationen (free) und Reihenfolgen (order): menschlich sinnvoll = realistische Lage am Telefon, eindeutige Frage, Antwortmöglichkeiten derselben Art (nicht eine Nummer neben einem Satz), genau eine richtige Antwort, keine Platzhalter, nicht trivial durch Wortwiederholung aus der Frage.\n" +
    "Für Tippen (gap) und Zuordnung (match): Drills für die Nummern der Agentur vor Ort, die man dem Kunden im Notfall durchgibt. Ein Trainer lässt solche Nummern bewusst üben; werte sie NICHT als unrealistisch ab, weil man nachschlagen könnte. Hier zählt nur: eindeutig, welcher Wert gemeint ist, und ein Wert (Nummer), kein Satz. Dann 4 oder 5.\n" +
    "Maßstab für ALLE Arten: Würde ein Trainer die Frage so stellen? Eine Frage, die nur einen Feldnamen oder eine Bezeichnung aus einer Datenbank vorliest („Wie lautet die Angabe X?“), ist keine Frage: 1 oder 2.";
  const r = await claude(system, txt, JUDGE_TOOL, 2500);
  for (const n of (r.noten || [])) { const q = qs[(n.n || 0) - 1]; if (q) { q.quality = Math.max(1, Math.min(5, Number(n.score) || 1)); q.judge_note = n.note ? String(n.note).slice(0, 300) : null; } }
  for (const q of qs) if (q.quality == null) { q.quality = 3; q.judge_note = "nicht bewertet"; }
}

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };
async function runProject(pid: string, chunkLimit: number, factLimit: number, doJudge: boolean): Promise<any> {
    const facts = await fetchAll((a, b) => sb.from("kb_facts").select("id,topic,zielgebiet,info_type,label,value,qualifier,source,source_document_id,source_locator,updated_at").eq("project_id", pid).eq("status", "active").range(a, b));
    const { data: docs } = await sb.from("kb_documents").select("id,title,doc_kind").eq("project_id", pid);
    const docTitles: Record<string, string> = {}; for (const d of (docs || [])) docTitles[d.id] = d.title;
    const { data: st } = await sb.from("coach_settings").select("topic_cap").eq("project_id", pid).maybeSingle(); const cap = (st && st.topic_cap) || 40;
    const existing = await fetchAll((a, b) => sb.from("coach_questions").select("id,fingerprint,status,source_kind,source_id,kind,topic,gen_version").eq("project_id", pid).range(a, b));
    const have = new Map(existing.map((e: any) => [e.fingerprint, e]));
    const doneFacts = new Set(existing.filter((e: any) => e.source_kind === "fact" && e.gen_version === GEN_VERSION && e.kind !== "gap" && e.kind !== "match").map((e: any) => e.source_id));
    const capCount: Record<string, number> = {}; for (const e of existing) if (e.status === "active") capCount[e.topic + "|" + e.kind] = (capCount[e.topic + "|" + e.kind] || 0) + 1;
    let inserted = 0, blocked = 0, aiErrors = 0;
    // Portionsweise: prüfen + speichern, sobald ein Paket fertig ist (Gateway-Timeout unkritisch, Fortschritt bleibt)
    const flush = async (qs: Q[]) => {
      const fresh: Q[] = [];
      for (const q of qs) { q.fingerprint = await fp(q.kind + "|" + q.source_id + "|" + q.difficulty + "|v" + GEN_VERSION + "|" + norm(q.prompt).slice(0, 80)); if (!have.has(q.fingerprint)) { have.set(q.fingerprint, q); fresh.push(q); } }
      if (!fresh.length) return;
      if (doJudge) { for (let i = 0; i < fresh.length; i += 8) { const part = fresh.slice(i, i + 8); try { await judge(part); } catch (_e) { for (const q of part) { q.quality = 3; q.judge_note = "Prüfer nicht erreichbar"; } } } }
      for (const q of fresh.sort((a, b) => (b.quality || 0) - (a.quality || 0))) {
        const key = q.topic + "|" + q.kind; const ok = (q.quality || 0) >= 4 && (capCount[key] || 0) < cap; if (ok) capCount[key] = (capCount[key] || 0) + 1;
        const { error } = await sb.from("coach_questions").insert({ project_id: pid, ...q, gen_version: GEN_VERSION, status: ok ? "active" : "blocked", judge_note: ok ? q.judge_note : ((q.quality || 0) < 4 ? "Prüfer: " + (q.judge_note || "unter 4") : "Deckel je Thema erreicht") });
        if (!error) { if (ok) inserted++; else blocked++; } }
    };
    // Regeln (Tippen, Zuordnung): nur was es noch nicht gibt
    await flush(ruleQuestions(facts, docTitles));
    // KI-Auswahl aus Fakten
    const byTopic: Record<string, any[]> = {}; for (const f of facts) (byTopic[f.topic] = byTopic[f.topic] || []).push(f);
    // Nachbarn = nahe Ablenker: gleiche Bezeichnung (anderes Zielgebiet/Thema) oder gleiche Art im selben Thema, und dieselbe Wert-Form
    // (Nummer neben Nummer, Adresse neben Adresse, Frist neben Frist). Sonst wäre die Auswahl trivial („AGB-Dokument“ neben einer Frist).
    const shape = (v: string) => { const t = String(v || ""); return /@/.test(t) ? "mail" : /https?:|www\./i.test(t) ? "url" : /\d{1,2}[:.]\d{2}|\buhr\b/i.test(t) ? "time" : /€|eur\b|chf\b|\bprozent|%/i.test(t) ? "money" : /\d{4,}/.test(t.replace(/\s/g, "")) ? "num" : /\d/.test(t) ? "numtext" : "text"; };
    const byLabel: Record<string, any[]> = {}; for (const f of facts) if (isFactish(f)) (byLabel[norm(f.label)] = byLabel[norm(f.label)] || []).push(f);
    const siblingsOf = (f: any) => { const sh = shape(f.value); const seen = new Set<string>([f.id]); const cand: { s: any; score: number }[] = [];
      const add = (x: any, score: number) => { if (seen.has(x.id) || !isFactish(x) || norm(x.value) === norm(f.value) || shape(x.value) !== sh) return; seen.add(x.id); cand.push({ s: x, score }); };
      for (const x of (byLabel[norm(f.label)] || [])) add(x, 3);
      for (const x of byTopic[f.topic]) if (x.info_type && x.info_type === f.info_type) add(x, 2);
      for (const x of byTopic[f.topic]) add(x, 1);
      return shuffle(cand.filter((c) => c.score >= 2)).sort((a, b) => b.score - a.score).slice(0, 6).map((c) => c.s); };
    const factPool = facts.filter((f) => isFactish(f) && !doneFacts.has(f.id) && siblingsOf(f).length >= 2);
    const factTodo = shuffle(factPool).slice(0, factLimit);
    const mcBatches: any[][] = []; for (let i = 0; i < factTodo.length; i += 6) mcBatches.push(factTodo.slice(i, i + 6));
    await pmap(mcBatches, 3, async (b) => { try { const qs = await aiMc(b, siblingsOf, docTitles); await flush(qs);
        // Fakten, die die KI übersprungen hat (skip / keine tauglichen Nachbarn): Merkposten, sonst jede Nacht neu bezahlt
        for (const f of b) if (!qs.some((q) => q.source_id === f.id)) await sb.from("coach_questions").insert({ project_id: pid, kind: "mc", difficulty: "mittel", topic: f.topic, zielgebiet: f.zielgebiet || null, prompt: "-", answer: {}, source_kind: "fact", source_id: f.id, source_label: "(kein Stoff)", status: "blocked", gen_by: "ai", gen_version: GEN_VERSION, fingerprint: await fp("nomc|" + f.id + "|v" + GEN_VERSION) }).then(() => {}, () => {});
      } catch (_e) { aiErrors++; } });
    // Situationen aus Prosa-Fakten + Abschnitten
    const prosePool = facts.filter((f) => isProse(f) && !doneFacts.has(f.id));
    const items: { ref: string; text: string; head: string; src: any }[] = shuffle(prosePool).slice(0, Math.max(6, Math.floor(factLimit / 3))).map((f) => ({ ref: f.id, text: lbl(f) + ": " + f.value, head: f.topic, src: { topic: f.topic, source_kind: "fact", source_id: f.id, source_label: srcLabel(f, docTitles), source_stamp: f.updated_at } }));
    const aiDocIds = (docs || []).filter((d) => ["coaching", "ablauf", "faq"].includes(d.doc_kind)).map((d) => d.id);
    let chunkPool = 0;
    if (aiDocIds.length) {
      const chunks = await fetchAll((a, b) => sb.from("kb_chunks").select("id,document_id,section,page,content,created_at").eq("project_id", pid).in("document_id", aiDocIds).range(a, b));
      const covered = new Set(existing.filter((e: any) => e.source_kind === "chunk" && e.gen_version === GEN_VERSION).map((e: any) => e.source_id));
      const todo = shuffle(chunks.filter((c: any) => !covered.has(c.id) && String(c.content || "").length >= 250)); chunkPool = todo.length;
      for (const c of todo.slice(0, chunkLimit)) items.push({ ref: c.id, text: String(c.content), head: (docTitles[c.document_id] || "Unterlage") + (c.section ? " / " + c.section : ""), src: { topic: c.section || "Schulungsunterlage", source_kind: "chunk", source_id: c.id, source_label: (docTitles[c.document_id] || "Unterlage") + (c.section ? " / " + c.section : "") + (c.page ? ", S. " + c.page : ""), source_stamp: c.created_at } });
    }
    // Abschnitte ohne Ergebnis als Merkposten (nicht jede Nacht neu bezahlen): blocked-Zeile je Abschnitt
    const sitBatches: typeof items[] = []; for (let i = 0; i < items.length; i += 3) sitBatches.push(items.slice(i, i + 3));
    await pmap(sitBatches, 3, async (b) => { try { const qs = await aiSituations(b); await flush(qs);
        for (const it of b) if (it.src.source_kind === "chunk" && !qs.some((q) => q.source_id === it.ref)) await sb.from("coach_questions").insert({ project_id: pid, kind: "free", difficulty: "mittel", topic: it.src.topic, prompt: "-", answer: {}, source_kind: "chunk", source_id: it.ref, source_label: "(kein Stoff)", status: "blocked", gen_by: "ai", gen_version: GEN_VERSION, fingerprint: await fp("none|" + it.ref + "|v" + GEN_VERSION) }).then(() => {}, () => {});
      } catch (_e) { aiErrors++; } });
    // Prosa-Fakten ohne Ergebnis ebenfalls merken
    for (const it of items.filter((x) => x.src.source_kind === "fact")) if (!have.has(await fp("free|" + it.ref + "|schwer|v" + GEN_VERSION + "|"))) { /* Fingerprint enthält Prompt, daher Merkposten über doneFacts-Zeile */ await sb.from("coach_questions").insert({ project_id: pid, kind: "free", difficulty: "mittel", topic: it.src.topic, prompt: "-", answer: {}, source_kind: "fact", source_id: it.ref, source_label: "(kein Stoff)", status: "blocked", gen_by: "ai", gen_version: GEN_VERSION, fingerprint: await fp("none|" + it.ref + "|v" + GEN_VERSION) }).then(() => {}, () => {}); }
    const { count: active } = await sb.from("coach_questions").select("id", { count: "exact", head: true }).eq("project_id", pid).eq("status", "active");
    const remaining = Math.max(0, factPool.length - factTodo.length) + Math.max(0, chunkPool - chunkLimit);
    return { project_id: pid, facts: facts.length, fact_batches: mcBatches.length, situation_batches: sitBatches.length, inserted, blocked, ai_errors: aiErrors, active, remaining };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* Cron */ }
  const onlyProject = typeof body.project_id === "string" ? body.project_id : null;
  const chunkLimit = Number.isFinite(body.ai_limit) ? Number(body.ai_limit) : 6;      // Abschnitte je Portion
  const factLimit = Number.isFinite(body.fact_limit) ? Number(body.fact_limit) : 36;   // Fakten je Portion (6 Pakete)
  const doJudge = body.judge !== false; const chain = body.chain !== false; const hops = Number(body.hops || 0);
  const projects = onlyProject ? [onlyProject] : [...new Set((await fetchAll((a, b) => sb.from("kb_facts").select("project_id").eq("status", "active").range(a, b))).map((r: any) => r.project_id))];
  // Arbeit im Hintergrund (Gateway-Timeout 150 s), Antwort sofort; Rest per Selbstaufruf in weiteren Portionen (max. 30 Sprünge)
  const work = async () => {
    for (const pid of projects) {
      try { const r = await runProject(pid, chunkLimit, factLimit, doJudge); console.log("[coach-generate]", JSON.stringify(r));
        if (chain && r.remaining > 0 && hops < 30) await fetch(Deno.env.get("SUPABASE_URL")! + "/functions/v1/coach-generate", { method: "POST", headers: { "Content-Type": "application/json", "Authorization": "Bearer " + Deno.env.get("SUPABASE_ANON_KEY")!, "apikey": Deno.env.get("SUPABASE_ANON_KEY")! }, body: JSON.stringify({ project_id: pid, ai_limit: chunkLimit, fact_limit: factLimit, judge: doJudge, chain: true, hops: hops + 1 }) });
      } catch (e) { console.error("[coach-generate] " + pid + " " + (e as Error).message); }
    }
  };
  // Nachprüfung der ganzen Bank mit dem Trainer-Maßstab: {"recheck":true,"project_id":…,"limit":80}; sperrt unter 4
  if (body.recheck === true) {
    const pid = onlyProject!; const lim = Math.max(8, Math.min(200, Number(body.limit) || 80));
    const { data: rows } = await sb.from("coach_questions").select("*").eq("project_id", pid).eq("status", "active").not("judge_note", "ilike", "Trainer-Maßstab:%").limit(lim);
    const list: Q[] = (rows || []) as any; let blocked = 0;
    for (let i = 0; i < list.length; i += 8) { const part = list.slice(i, i + 8); part.forEach((q: any) => { q.quality = null; }); try { await judge(part); } catch (_e) { continue; }
      for (const q of part as any[]) { const ok = (q.quality || 0) >= 4; if (!ok) blocked++; await sb.from("coach_questions").update({ quality: q.quality, judge_note: "Trainer-Maßstab: " + (q.judge_note || ""), status: ok ? "active" : "blocked", updated_at: new Date().toISOString() }).eq("id", q.id); } }
    const { count } = await sb.from("coach_questions").select("id", { count: "exact", head: true }).eq("project_id", pid).eq("status", "active").not("judge_note", "ilike", "Trainer-Maßstab:%");
    return json({ ok: true, checked: list.length, blocked, remaining: count || 0 });
  }
  if (body.sync === true) { const out: any[] = []; for (const pid of projects) out.push(await runProject(pid, chunkLimit, factLimit, doJudge)); return json({ ok: true, report: out }); }
  EdgeRuntime.waitUntil(work());
  return json({ ok: true, started: true, projects, portion: { ai_limit: chunkLimit, fact_limit: factLimit }, hops });
});
