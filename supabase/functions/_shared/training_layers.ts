// Miriams drei Ebenen je Frage (Warum · Einwand · Anwendung), NUR aus den Unterlagen des Partners. Geteilt von training-enrich
// (nächtliche Befüllung der Fragenbank, coach_questions.layers) und training-build (fehlende Ebenen beim Anlegen nachziehen).
import { claudeTool } from "./coach_grade.ts";
export async function pmap<T, R>(items: T[], n: number, f: (t: T) => Promise<R>): Promise<R[]> { const out: R[] = new Array(items.length); let i = 0; await Promise.all(Array(Math.min(n, items.length)).fill(0).map(async () => { while (i < items.length) { const k = i++; try { out[k] = await f(items[k]); } catch (e) { out[k] = (e as any); } } })); return out; }
const LAYER_TOOL = { name: "ebenen", input_schema: { type: "object", properties: { fragen: { type: "array", items: { type: "object", properties: {
  id: { type: "string" },
  why: { type: "string", description: "WARUM es so ist: 2-4 Sätze Erklärung des Hintergrunds, nur aus dem Kontext. Duzen." },
  objection_customer: { type: "string", description: "EINWAND: was ein Kunde typischerweise dagegen sagt (ein Satz in Kundenworten, Sie-Form). Leer lassen, wenn zu dieser Frage kein echter Einwand denkbar ist (z. B. reine Nummer)." },
  objection_answer: { type: "string", description: "Was du dem Kunden darauf sagst: 2-3 Sätze, wörtlich so, wie du es am Telefon sagst (Sie-Form), nur aus dem Kontext. Leer, wenn kein Einwand." },
  apply: { type: "string", description: "ANWENDUNG im Gespräch: eine konkrete Formulierung oder ein kurzer Ablauf, wie du das im Kundengespräch einsetzt (2-3 Sätze). Leer, wenn der Kontext dazu nichts hergibt." },
}, required: ["id", "why"] } } }, required: ["fragen"] } };

export async function buildLayers(admin: any, pid: string, list: any[]): Promise<Record<string, any>> {
  // Kontext je Frage: Quelle (Fakt/Abschnitt) + Register/Abschnitte per kb_retrieve
  const { data: docs } = await admin.from("kb_documents").select("id,title").eq("project_id", pid); const docTitle: Record<string, string> = {}; for (const d of (docs || [])) docTitle[d.id] = d.title;
  const ctxFor = async (x: any) => {
    const parts: string[] = [];
    if (x.source_kind === "fact") { const { data: f } = await admin.from("kb_facts").select("topic,zielgebiet,label,value,qualifier").eq("id", x.source_id).maybeSingle(); if (f) parts.push("REGISTER: " + f.topic + (f.zielgebiet ? " · " + f.zielgebiet : "") + " · " + f.label + ": " + f.value); }
    if (x.source_kind === "chunk") { const { data: c } = await admin.from("kb_chunks").select("section,content,document_id").eq("id", x.source_id).maybeSingle(); if (c) parts.push("ABSCHNITT [" + (docTitle[c.document_id] || "Unterlage") + (c.section ? " / " + c.section : "") + "]: " + c.content); }
    // Zusatzkontext: Register desselben Themas (und Zielgebiets) + Abschnitte, die die Kernwörter von Thema/Frage enthalten
    let fq = admin.from("kb_facts").select("topic,zielgebiet,label,value").eq("project_id", pid).eq("status", "active").eq("topic", x.topic); if (x.zielgebiet) fq = fq.eq("zielgebiet", x.zielgebiet);
    const { data: fs } = await fq.limit(6); for (const f of (fs || [])) { const t = "REGISTER: " + f.topic + (f.zielgebiet ? " · " + f.zielgebiet : "") + " · " + f.label + ": " + f.value; if (!parts.includes(t)) parts.push(t); }
    const words = [...new Set((x.topic.split(/[·:,]/)[0] + " " + x.prompt).split(/[^A-Za-zÄÖÜäöüß]+/).filter((w: string) => w.length >= 6 && !/^(welche|welcher|welches|kunde|kundin|fragt|sagst|antwort|richtig|folgende|folgenden|telefon|möchte|braucht)$/i.test(w)))].sort((a, b) => b.length - a.length).slice(0, 3);
    for (const w of words) { const { data: cs } = await admin.from("kb_chunks").select("section,content,document_id").eq("project_id", pid).ilike("content", "%" + w + "%").limit(2); for (const c of (cs || [])) { const t = "ABSCHNITT [" + (docTitle[c.document_id] || "Unterlage") + (c.section ? " / " + c.section : "") + "]: " + String(c.content || "").slice(0, 900); if (!parts.some((p) => p.slice(0, 80) === t.slice(0, 80))) parts.push(t); } if (parts.length >= 7) break; }
    return parts.slice(0, 7).join("\n\n");
  };
  const ctx = await pmap(list, 4, ctxFor);
  // Ebenen je Frage (4 je Aufruf)
  const system = "Du bist Miriam, KI-Trainerin von TIVE 360°. Du bereitest die Auflösung von Schulungsfragen für Call-Center-Kräfte eines Reiseveranstalters auf. " +
    "Regel Nummer eins: NUR aus dem KONTEXT (Register-Einträge und Abschnitte der Unterlage). Nichts dazu erfinden, keine Zahlen, Namen oder Regeln, die nicht im Kontext stehen. " +
    "Gibt der Kontext für eine Ebene nichts her, lässt du sie LEER; eine leere Ebene ist besser als eine erfundene. Die Person, die lernt, duzt du IMMER („Sag dem Kunden …“, nie „Sagen Sie“); nur die Sätze an den Kunden selbst sind in Sie-Form. Kurze Sätze, keine Gedankenstriche, keine Floskeln.";
  const batches: number[][] = []; for (let i = 0; i < list.length; i += 4) batches.push(list.slice(i, i + 4).map((_x, j) => i + j));
  const layers: Record<string, any> = {};
  await pmap(batches, 3, async (idx) => {
    const txt = idx.map((i) => { const x = list[i]; const sol = x.kind === "mc" ? (x.options || []).find((o: any) => o.key === x.answer?.key)?.text : x.kind === "gap" ? (x.answer?.accept || [])[0] : x.kind === "free" ? (x.answer?.model_answer || (x.answer?.must || []).join("; ")) : x.kind === "order" ? (x.answer?.sequence || []).join(" → ") : JSON.stringify(x.answer?.pairs || {});
      return "FRAGE " + x.id + "\n  Thema: " + x.topic + "\n  Frage: " + x.prompt + "\n  Richtige Antwort: " + sol + (x.explanation ? "\n  Auflösung: " + x.explanation : "") + "\n  KONTEXT:\n" + (ctx[i] || "(kein Kontext)"); }).join("\n\n=====\n\n");
    const r = await claudeTool(system, txt, LAYER_TOOL, 3500);
    for (const f of (r.fragen || [])) layers[f.id] = f;
  });
  const out: Record<string, any> = {};
  for (const x of list) { const l = layers[x.id]; if (!l) continue; out[x.id] = { why: String(l.why || "").trim() || null, objection: (l.objection_customer && l.objection_answer) ? { customer: String(l.objection_customer).trim(), you: String(l.objection_answer).trim() } : null, apply: String(l.apply || "").trim() || null }; }
  return out;
}
