// Schulung bauen (HR, Nutzer-JWT, Recht: Bereich wissen = bearbeiten). Miriam wählt Fragen aus der geprüften Fragenbank
// (quality ≥ 4, gewünschte Themen, reihum, Freitext ≤ 1/3) und baut je Frage drei Ebenen NUR aus den Unterlagen des Partners:
// Warum (Erklärung), Einwand (Kunde widerspricht: was sagst du), Anwendung (Formulierung im Gespräch). Wo die Unterlagen nichts
// hergeben, bleibt die Ebene leer (nie erfinden). Ergebnis geht als Entwurf zurück; HR prüft und speichert (trainings.questions).
// Deploy: supabase functions deploy training-build --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { norm, shuffle, claudeTool } from "../_shared/coach_grade.ts";
import { buildLayers, pmap } from "../_shared/training_layers.ts";

const SB_URL = Deno.env.get("SUPABASE_URL")!, ANON = Deno.env.get("SUPABASE_ANON_KEY")!, SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, s = 200) => { if (s >= 400) console.error("[training-build] " + s + " " + JSON.stringify(b)); return new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } }); };
const admin = createClient(SB_URL, SERVICE);

const INTRO_TOOL = { name: "intro", input_schema: { type: "object", properties: { intro: { type: "string", description: "Begrüßung zur Schulung: GENAU EIN Satz, höchstens 20 Wörter, sagt worum es geht. Duzen, warm, ohne Floskeln, keine Gedankenstriche, kein Hallo." }, minutes: { type: "integer", description: "geschätzte Dauer in Minuten" } }, required: ["intro", "minutes"] } };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const auth = req.headers.get("Authorization") || ""; const user = createClient(SB_URL, ANON, { global: { headers: { Authorization: auth } } });
  const { data: u } = await user.auth.getUser(); if (!u?.user) return json({ error: "Nicht angemeldet." }, 401);
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* leer */ }
  const pid = String(body.project_id || ""); if (!pid) return json({ error: "Partner fehlt." }, 400);
  const { data: mode } = await admin.rpc("perm_mode", { p_uid: u.user.id, p_area: "wissen" }); const { data: pok } = await admin.rpc("perm_proj_ok", { p_uid: u.user.id, p_area: "wissen", p_project: pid });
  if (mode !== "edit" || pok === false) return json({ error: "Kein Recht, Schulungen für diesen Partner anzulegen." }, 403);
  const topics: string[] = Array.isArray(body.topics) ? body.topics.filter(Boolean) : []; const n = Math.max(3, Math.min(25, Number(body.count) || 10));
  const title = String(body.title || "Schulung");

  // 1) Fragen wählen: geprüft, gewünschte Themen, reihum über Themen, Arten gemischt, Freitext ≤ 1/3
  let q = admin.from("coach_questions").select("*").eq("project_id", pid).eq("status", "active").gte("quality", 4); if (topics.length) q = q.in("topic", topics);
  const { data: bank } = await q.limit(3000); const rows = shuffle(bank || []);
  const groups = new Map<string, any[]>(); for (const r of rows) (groups.get(r.topic) || groups.set(r.topic, []).get(r.topic))!.push(r);
  const order = topics.length ? topics.filter((t) => groups.has(t)) : [...groups.keys()]; const capFree = Math.max(1, Math.ceil(n / 2));   // Situationen sind in der Schulung der wertvolle Teil
  // Ähnliche Situationen (dieselbe Frage für fünf Zielgebiete) nur einmal: Wortmenge ohne Orte vergleichen
  const bag = (x: any) => new Set(norm(x.prompt).replace(norm(x.zielgebiet || "zzz"), "").split(" ").filter((w) => w.length >= 4));
  const similar = (a: Set<string>, b: Set<string>) => { let hit = 0; for (const w of a) if (b.has(w)) hit++; return hit / Math.max(1, Math.min(a.size, b.size)) >= 0.6; };
  const picked: any[] = []; const bags: Set<string>[] = []; let freeN = 0;
  for (let k = 0; picked.length < n; k++) { let any = false; for (const t of order) { const arr = groups.get(t) || []; const x = arr[k]; if (!x) continue; any = true; if (picked.length >= n) break; const bg = bag(x); if (bags.some((b) => similar(b, bg))) continue; if (x.kind === "free") { if (freeN >= capFree) continue; freeN++; } bags.push(bg); picked.push(x); } if (!any) break; }
  // Freitext-Deckel hat Plätze offen gelassen, obwohl es Stoff gibt: mit Situationen nachfüllen, Themen ohne Frage zuerst
  if (picked.length < n) { // reihum über die Themen, Themen ohne Frage zuerst, damit kein Thema leer ausgeht
    const cnt: Record<string, number> = {}; for (const x of picked) cnt[x.topic] = (cnt[x.topic] || 0) + 1;
    const rest = rows.filter((x) => !picked.includes(x) && !bags.some((b) => similar(b, bag(x))));
    while (picked.length < n && rest.length) { rest.sort((a, b) => (cnt[a.topic] || 0) - (cnt[b.topic] || 0)); const x = rest.shift()!; bags.push(bag(x)); picked.push(x); cnt[x.topic] = (cnt[x.topic] || 0) + 1; } }
  if (!picked.length) return json({ error: "Zu diesen Themen gibt es keine geprüften Fragen." }, 404);
  // Freitext ans Ende, Rest gemischt
  const list = [...shuffle(picked.filter((x) => x.kind !== "free")), ...picked.filter((x) => x.kind === "free")];

  // 2) Ebenen: aus der Fragenbank (nachts befüllt), fehlende jetzt bauen
  const missing = list.filter((x) => !x.layers); const built = missing.length ? await buildLayers(admin, pid, missing) : {};
  const layers: Record<string, any> = {}; for (const x of list) layers[x.id] = x.layers || built[x.id] || {};
  for (const x of missing) if (built[x.id]) await admin.from("coach_questions").update({ layers: built[x.id], layers_at: new Date().toISOString() }).eq("id", x.id);
  // 4) Intro
  let intro = "", minutes = Math.max(3, Math.round(list.length * 1.5));
  try { const r = await claudeTool("Du bist Miriam, KI-Trainerin von TIVE 360°. Du begrüßt eine Kollegin zu einer kurzen Schulung mit genau einem Satz: worum es geht. Duzen, warm, konkret, keine Floskeln, keine Gedankenstriche.", "Schulung: " + title + "\nThemen: " + (topics.length ? topics.join(", ") : [...new Set(list.map((x) => x.topic))].join(", ")) + "\nAnzahl Fragen: " + list.length + "\nArten: " + [...new Set(list.map((x) => x.kind))].join(", "), INTRO_TOOL, 500); intro = String(r.intro || ""); if (r.minutes) minutes = Math.max(3, Math.min(60, Number(r.minutes))); } catch (_e) { /* Intro bleibt leer */ }
  const out = list.map((x) => { const l = layers[x.id] || {}; return { id: x.id, kind: x.kind, difficulty: x.difficulty, topic: x.topic, zielgebiet: x.zielgebiet, prompt: x.prompt, options: x.options, answer: x.answer, explanation: x.explanation, source_label: x.source_label, why: l.why || null, objection: l.objection || null, apply: l.apply || null }; });
  return json({ ok: true, intro, minutes, questions: out, topics: [...new Set(out.map((x) => x.topic))] });
});
