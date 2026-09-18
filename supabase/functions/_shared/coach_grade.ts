// Geteilt von coach-session (Coach im Portal) und training-run (Schulung per Link): Normalisierung, Frage ohne Lösung,
// Bewertung je Frageart (deterministisch) und Freitext-Bewertung durch Claude anhand der Vorlage.
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
const MODEL = "claude-sonnet-5";
export const norm = (s: any) => String(s ?? "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9@.]+/g, " ").trim();
export const digits = (s: any) => String(s ?? "").replace(/\D+/g, "");
export const shuffle = <T,>(a: T[]) => { const b = a.slice(); for (let i = b.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [b[i], b[j]] = [b[j], b[i]]; } return b; };

export function publicQ(q: any) {   // ohne Lösung an den Mitarbeiter
  return { id: q.id, kind: q.kind, difficulty: q.difficulty, topic: q.topic, zielgebiet: q.zielgebiet, prompt: q.prompt,
    options: q.kind === "mc" ? (q.options || []).map((o: any) => ({ key: o.key, text: o.text })) : q.kind === "match" ? q.options : q.kind === "order" ? shuffle(q.options || []) : null };
}

// ── Bewertung ─────────────────────────────────────────────────────────────────────────────────────────
export function gradeMc(q: any, a: any) { const key = String(q.answer?.key); const chosen = String(a?.key || ""); const ok = chosen === key;
  const opt = (q.options || []).find((o: any) => o.key === chosen); const why = opt && opt.why ? "Deine Wahl (" + chosen + ") ist " + opt.why + "." : "";
  return { points: ok ? 1 : 0, feedback: ok ? "" : ("Nicht ganz. " + why + " Richtig ist " + key + ". " + (q.explanation ? "Merk dir: " + q.explanation : "")).replace(/\s+/g, " ").trim() }; }
export function gradeGap(q: any, a: any) {
  const given = String(a?.text || ""); const acc: string[] = q.answer?.accept || [];
  const ok = acc.some((v) => { const dv = digits(v), dg = digits(given); if (dv.length >= 5) return dv === dg; return norm(v) === norm(given); });
  let partial = 0; if (!ok) for (const v of acc) { const dv = digits(v), dg = digits(given); if (dv.length >= 6 && dv.length === dg.length) { let diff = 0; for (let i = 0; i < dv.length; i++) if (dv[i] !== dg[i]) diff++; if (diff === 1) partial = 0.5; } }
  return { points: ok ? 1 : partial, feedback: ok ? "" : partial ? "Fast: eine Ziffer daneben. Richtig ist " + acc[0] + "." : "Richtig ist: " + acc[0] + "." + (q.explanation ? " Merk dir: " + q.explanation : "") };
}
export function gradeMatch(q: any, a: any) { const pairs = q.answer?.pairs || {}; const given = a?.pairs || {}; const keys = Object.keys(pairs); const hit = keys.filter((k) => norm(given[k]) === norm(pairs[k])).length; const wrong = keys.filter((k) => norm(given[k]) !== norm(pairs[k]));
  return { points: keys.length ? Math.round(hit / keys.length * 100) / 100 : 0, feedback: hit === keys.length ? "Alles richtig zugeordnet." : hit + " von " + keys.length + " richtig. " + wrong.map((k) => k + " gehört zu " + pairs[k]).join(", ") + "." }; }
export function gradeOrder(q: any, a: any) { const seq: string[] = q.answer?.sequence || []; const given: string[] = Array.isArray(a?.sequence) ? a.sequence : []; const hit = seq.filter((s, i) => norm(given[i]) === norm(s)).length;
  const first = seq.findIndex((s, i) => norm(given[i]) !== norm(s));
  return { points: seq.length ? Math.round(hit / seq.length * 100) / 100 : 0, feedback: hit === seq.length ? "Reihenfolge stimmt." : hit + " von " + seq.length + " Schritten an der richtigen Stelle." + (first >= 0 ? " Ab Schritt " + (first + 1) + " weicht es ab: dort kommt „" + seq[first] + "“." : "") }; }

const GRADE_TOOL = { name: "bewertung", input_schema: { type: "object", properties: {
  hits: { type: "array", items: { type: "string" }, description: "Kernpunkte aus der Vorlage, die inhaltlich in der Antwort vorkommen (wörtlich aus der Vorlage übernehmen)" },
  missing: { type: "array", items: { type: "string" }, description: "Kernpunkte aus der Vorlage, die fehlen" },
  feedback: { type: "string", description: "2-3 Sätze an die Kollegin: was gut war, was gefehlt hat und WIE sie es beim nächsten Mal sagt. Konkret, freundlich, duzen. Keine Floskeln." },
  wrong: { type: "boolean", description: "true nur, wenn die Antwort etwas sachlich Falsches behauptet (falsche Nummer, falscher Ablauf)" },
}, required: ["hits", "missing", "feedback", "wrong"] } };
export async function gradeFree(q: any, a: any, agentName: string): Promise<{ points: number; feedback: string; rubric: any }> {
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


// Ein Werkzeug-Aufruf (erzwungen), Antwort = Tool-Input
export async function claudeTool(system: string, user: string, tool: any, maxTokens = 2500): Promise<any> {
  const resp = await fetch("https://api.anthropic.com/v1/messages", { method: "POST", headers: { "x-api-key": ANTHROPIC_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({ model: MODEL, max_tokens: maxTokens, system, tools: [tool], tool_choice: { type: "tool", name: tool.name }, messages: [{ role: "user", content: user }] }) });
  const data = await resp.json(); if (!resp.ok) throw new Error(data?.error?.message || String(resp.status));
  return (data.content || []).find((c: any) => c.type === "tool_use")?.input || {};
}
export function gradeAny(q: any, a: any, agentName: string): Promise<{ points: number; feedback: string; rubric?: any }> | { points: number; feedback: string; rubric?: any } {
  return q.kind === "mc" ? gradeMc(q, a) : q.kind === "gap" ? gradeGap(q, a) : q.kind === "match" ? gradeMatch(q, a) : q.kind === "order" ? gradeOrder(q, a) : gradeFree(q, a, agentName);
}
