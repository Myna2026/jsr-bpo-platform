// Edge Function: Management-Calls KI. Zwei Modi, beide nur für die 4er-Freigabeliste (is_mgmt_call_user).
//  - extract (M3): eingefügtes Protokoll -> Vorschläge für offene Punkte (Bereich/Was/Wer/bis wann). Ordnet den
//    Bereich zu; ist es unklar, bleibt der Bereich leer (der Mensch wählt ihn im Bestätigen-Schritt).
//    Erfindet NICHTS: nur was im Protokoll steht. Speichert nichts — der Mensch bestätigt.
//  - analyze (M4): liest alle Calls + offene/erledigte Punkte (über den User-Client, RLS greift) und wertet aus:
//    was wiederholt sich, was bleibt liegen, wo dreht man sich im Kreis. Nur Beobachtung, keine Wertung, kein Erfinden.
// Deploy: supabase functions deploy mgmt-call-ai --use-api --no-verify-jwt
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

const MODEL = "claude-sonnet-5";
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;

const EXTRACT_TOOL = {
  name: "punkte",
  description: "Der Freitext eines Management-Calls, aufbereitet: eine kurze Zusammenfassung und die nachverfolgbaren Punkte in sinnvollen Gruppen. Nur was im Text steht.",
  input_schema: {
    type: "object",
    properties: {
      zusammenfassung: { type: "string", description: "2-4 Sätze: worum ging es in diesem Call, das Wesentliche. Sachlich, aus dem Text." },
      items: {
        type: "array",
        description: "je konkrete Aufgabe/Vorhaben/Vereinbarung mit Handlungsbedarf ein Eintrag. Reine Infos ohne To-do NICHT aufnehmen.",
        items: {
          type: "object",
          properties: {
            text: { type: "string", description: "der Punkt kurz und klar (was ist zu tun / was wurde vorgenommen), aus dem Protokoll" },
            bereich: { type: "string", description: "die sinnvolle Gruppe. Bevorzugt eine aus der vorgegebenen Liste; passt keine, bilde eine kurze eigene. Nie leer, wenn eine Gruppe erkennbar ist." },
            owner: { type: ["string", "null"], description: "die zuständige Person genau so, wie im Text genannt (z. B. 'Edi'), falls für DIESE Aufgabe jemand als zuständig genannt ist; sonst null (dann bleibt der Punkt allgemein für die Runde). Achtung: eine Person, die BEARBEITET wird (Bewerber, der kontaktiert/eingesetzt wird), ist NICHT der owner." },
            due_date: { type: ["string", "null"], description: "Fälligkeit als YYYY-MM-DD, aus einer Frist im Text (auch relativ: 'bis Freitag', 'Monatsende', 'nächste Woche') relativ zu HEUTE aufgelöst; sonst null" },
            target_n: { type: ["number", "null"], description: "ZIEL als Zahl, wenn ein Mengenziel genannt ist (z. B. '10 Leute einstellen' -> 10); sonst null" },
            actual_n: { type: ["number", "null"], description: "IST/geschafft als Zahl, wenn genannt (z. B. 'es wurden 6' -> 6); sonst null. So erkennt das System: offen = Ziel minus Ist." },
          },
          required: ["text", "bereich"],
        },
      },
    },
    required: ["zusammenfassung", "items"],
  },
};

const ANALYZE_TOOL = {
  name: "auswertung",
  description: "Nüchterne Auswertung der Management-Calls. Nur beobachten, nicht bewerten, nichts erfinden.",
  input_schema: {
    type: "object",
    properties: {
      ueberblick: { type: "string", description: "2-4 Sätze: Gesamtbild der letzten Calls (Menge offener Punkte, grobe Schwerpunkte). Sachlich." },
      wiederkehrend: {
        type: "array", description: "Themen, die in mehreren Calls auftauchen (gleiches Thema erneut besprochen).",
        items: { type: "object", properties: { thema: { type: "string" }, hinweis: { type: "string", description: "worin es sich zeigt, kurz" } }, required: ["thema", "hinweis"] },
      },
      liegen_geblieben: {
        type: "array", description: "offene Punkte, die schon länger offen sind oder überfällig — was hängt.",
        items: { type: "object", properties: { punkt: { type: "string" }, hinweis: { type: "string", description: "seit wann / warum auffällig" } }, required: ["punkt", "hinweis"] },
      },
      im_kreis: {
        type: "array", description: "Themen, bei denen man sich im Kreis dreht: immer wieder besprochen, aber nicht abgeschlossen. Leer, wenn nichts erkennbar.",
        items: { type: "object", properties: { thema: { type: "string" }, hinweis: { type: "string" } }, required: ["thema", "hinweis"] },
      },
      bilanz: {
        type: "array", description: "Was vorgenommen wurde und was daraus geworden ist — vor allem bei Zahlenzielen (z. B. '10 geplant, 6 geschafft, 4 offen'). Nutze die Ziel/Ist-Angaben und den Status (erledigt/offen/teilweise). Leer, wenn nichts Zählbares.",
        items: { type: "object", properties: { vorgenommen: { type: "string", description: "was man sich vorgenommen hatte" }, geworden: { type: "string", description: "was daraus wurde (Stand)" } }, required: ["vorgenommen", "geworden"] },
      },
    },
    required: ["ueberblick"],
  },
};

function todayIso(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate());
}

let LAST_STOP = "";
async function callClaude(system: string, userText: string, tool: any, toolName: string, maxTokens: number) {
  const resp = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": ANTHROPIC_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({ model: MODEL, max_tokens: maxTokens, system, tools: [tool], tool_choice: { type: "tool", name: toolName }, messages: [{ role: "user", content: userText }] }),
  });
  const data = await resp.json();
  if (!resp.ok) throw new Error(data?.error?.message || ("HTTP " + resp.status));
  LAST_STOP = String(data?.stop_reason || "");
  const t = (data.content || []).find((c: any) => c.type === "tool_use");
  if (!t) throw new Error("Keine verwertbare Antwort.");
  return t.input || {};
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST erwartet" }, 405);
  const auth = req.headers.get("Authorization") || "";
  if (!auth) return json({ error: "Nicht angemeldet." }, 401);
  const sb = createClient(SB_URL, ANON, { global: { headers: { Authorization: auth } } });

  const { data: udata } = await sb.auth.getUser();
  if (!udata?.user?.id) return json({ error: "Sitzung ungültig." }, 401);

  // Zugriff: nur die Management-Call-Freigabeliste.
  const { data: okData, error: okErr } = await sb.rpc("is_mgmt_call_user");
  if (okErr || okData !== true) return json({ error: "Kein Zugriff auf die Management-Calls." }, 403);
  if (!ANTHROPIC_KEY) return json({ error: "Der KI-Schlüssel ist noch nicht hinterlegt." }, 503);

  let body: any = {}; try { body = await req.json(); } catch { /* egal */ }
  const mode = String(body?.mode || "").trim();

  // ── M3: Punkte aus Protokoll ziehen ──────────────────────────────────────
  if (mode === "extract") {
    const text = String(body?.text || "").trim();
    const bereiche: string[] = Array.isArray(body?.bereiche) ? body.bereiche.filter((x: any) => typeof x === "string") : [];
    if (!text) return json({ error: "Kein Protokoll übergeben." }, 400);

    // Extraktion OHNE Roster im Prompt (schlank und zuverlässig). Der Namensabgleich passiert danach serverseitig.
    const system =
      "Du bereitest den Freitext eines Management-Calls auf. Das ist die EINZIGE Eingabe des Teams — alles andere " +
      "leitest du ab. Mach daraus: (1) eine kurze Zusammenfassung, (2) die nachverfolgbaren Punkte (Aufgaben, " +
      "Vorhaben, Vereinbarungen mit Handlungsbedarf) in sinnvollen Gruppen. Reine Infos ohne To-do NICHT als Punkt.\n\n" +
      "EISERNE REGELN:\n" +
      "- Nimm NUR, was im Text steht. Erfinde nichts, keine Namen, Fristen oder Zahlen, die nicht dastehen.\n" +
      "- Gruppiere sinnvoll: bevorzugt eine Gruppe aus dieser Liste — " + (bereiche.length ? bereiche.join(", ") : "(keine Liste vorgegeben)") + " —, " +
      "passt keine, bilde eine kurze eigene Gruppe. Verwandte Punkte in dieselbe Gruppe.\n" +
      "- ZUSTÄNDIGKEIT: Wird für eine Aufgabe eine zuständige Person genannt ('Edi macht das', 'Ylli klärt das'), setze owner auf den Namen " +
      "wie geschrieben. Wird eine Person nur BEARBEITET (Bewerber, der kontaktiert oder eingesetzt wird), ist sie NICHT owner -> owner=null. " +
      "Steht keine zuständige Person, owner=null (Punkt bleibt allgemein). Der Abgleich mit den Mitarbeiterdaten geschieht danach automatisch.\n" +
      "- ZAHLEN: Mengenziel + Ergebnis ('10 einstellen, es wurden 6') -> target_n=10, actual_n=6 (System rechnet 4 offen). Nur wenn Zahlen dastehen.\n" +
      "- FRISTEN: Auch relative Angaben in ein Datum (YYYY-MM-DD) wandeln, relativ zu HEUTE = " + todayIso() + ". " +
      "'bis Freitag' = kommender Freitag; 'nächste Woche' = Montag der Folgewoche; 'Monatsende' = letzter Tag des aktuellen Monats; " +
      "'in zwei Wochen' = HEUTE + 14 Tage. Ohne Frist: due_date=null.";
    let out: any;
    try { out = await callClaude(system, "FREITEXT DES CALLS:\n" + text.slice(0, 12000), EXTRACT_TOOL, "punkte", 8000); }
    catch (e) { return json({ error: "Die KI ist gerade nicht erreichbar: " + (e as Error).message }, 502); }
    if (LAST_STOP === "max_tokens") return json({ error: "Der Text war für einen Durchgang zu lang. Bitte etwas kürzen oder in zwei Calls aufteilen." }, 502);
    const num = (v: any) => (typeof v === "number" && isFinite(v)) ? v : null;

    // Namensabgleich serverseitig (deterministisch, kein LLM): owner-Name -> Mitarbeiter-Datensatz.
    const EXCLUDED = new Set(["rejected_by_us", "rejected_by_employee", "rejected_by_client", "blacklist", "terminated_by_us", "terminated_by_employee", "parking"]);
    const { data: emps } = await sb.from("employees_masked_lite").select("id,first_name,last_name,status").limit(2000);
    const roster = (Array.isArray(emps) ? emps : [])
      .filter((e: any) => e && (e.first_name || e.last_name) && !EXCLUDED.has(String(e.status || "")))
      .map((e: any) => ({ id: e.id, first: String(e.first_name || ""), last: String(e.last_name || ""), full: ((e.first_name || "") + " " + (e.last_name || "")).trim() }));
    const norm = (s: string) => s.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/\s+/g, " ").trim();
    const matchOwner = (raw: string) => {
      const q = norm(raw); if (!q) return null;
      let m = roster.filter((r) => norm(r.full) === q); if (m.length === 1) return m[0];   // ganzer Name
      m = roster.filter((r) => norm(r.first) === q); if (m.length === 1) return m[0];        // exakter Vorname
      if (q.length >= 3) { m = roster.filter((r) => norm(r.first).startsWith(q)); if (m.length === 1) return m[0]; }  // Kurzform 'Edi'->'Edinela', nur eindeutig
      // Vorname als erstes Wort der Nennung (z. B. 'Edi Krasniqi' -> Vorname 'Edi')
      const firstTok = q.split(" ")[0];
      if (firstTok.length >= 3) { m = roster.filter((r) => norm(r.first) === firstTok || norm(r.first).startsWith(firstTok)); if (m.length === 1) return m[0]; }
      return null;
    };
    const items = (Array.isArray(out.items) ? out.items : [])
      .filter((it: any) => it && String(it.text || "").trim())
      .map((it: any) => {
        const ber = (it.bereich && String(it.bereich).trim()) || "";
        const due = typeof it.due_date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(it.due_date) ? it.due_date : null;
        const rawOwner = (it.owner && String(it.owner).trim()) || null;
        const hit = rawOwner ? matchOwner(rawOwner) : null;
        return { text: String(it.text).trim(), bereich: ber, owner: hit ? hit.full : rawOwner, owner_employee_id: hit ? hit.id : null, due_date: due, target_n: num(it.target_n), actual_n: num(it.actual_n) };
      });
    return json({ ok: true, summary: String(out.zusammenfassung || "").trim(), items });
  }

  // ── M4: Auswertung über alle Calls (Daten serverseitig über RLS lesen) ────
  if (mode === "analyze") {
    const from = typeof body?.from === "string" && /^\d{4}-\d{2}-\d{2}$/.test(body.from) ? body.from : null;   // Zeitraum-Anfang (optional)
    let cq = sb.from("mgmt_calls").select("id,call_date,title,body").order("call_date", { ascending: false }).limit(60);
    if (from) cq = cq.gte("call_date", from);
    const { data: calls } = await cq;
    const cl = Array.isArray(calls) ? calls : [];
    const callIds = cl.map((c: any) => c.id);
    let it: any[] = [];
    if (callIds.length) {
      const { data: items } = await sb.from("mgmt_call_items").select("bereich,text,owner,due_date,status,target_n,actual_n,progress_note,created_at,call_id").in("call_id", callIds).order("created_at", { ascending: false }).limit(600);
      it = Array.isArray(items) ? items : [];
    }
    if (!cl.length && !it.length) return json({ ok: true, ueberblick: "Für den gewählten Zeitraum sind keine Calls erfasst.", wiederkehrend: [], liegen_geblieben: [], im_kreis: [], bilanz: [] });
    const today = todayIso();
    const numInfo = (x: any) => (x.target_n != null) ? (" [Ziel " + x.target_n + (x.actual_n != null ? ", geschafft " + x.actual_n + ", offen " + Math.max(0, Number(x.target_n) - Number(x.actual_n)) : "") + "]") : (x.progress_note ? " [Stand: " + x.progress_note + "]" : "");
    const line = (x: any) => "- [" + (x.bereich || "ohne Gruppe") + "] " + x.text + (x.owner ? " (Wer: " + x.owner + ")" : "") + (x.due_date ? " (bis " + x.due_date + (x.status !== "done" && x.due_date < today ? ", ÜBERFÄLLIG" : "") + ")" : "") + numInfo(x);
    const callsTxt = cl.map((c: any) => "• " + (c.call_date || "") + (c.title ? " — " + c.title : "") + "\n" + String(c.body || "").replace(/\s+/g, " ").slice(0, 1000)).join("\n\n");
    const openTxt = it.filter((x: any) => x.status === "open" || x.status === "partial").map(line).join("\n");
    const doneTxt = it.filter((x: any) => x.status === "done").map(line).join("\n");
    const system =
      "Du wertest die Protokolle einer wiederkehrenden Management-Runde aus" + (from ? " (Zeitraum ab " + from + ")" : "") + ". Sei nüchtern und knapp. " +
      "NUR beobachten, nicht bewerten, keine Ratschläge, nichts erfinden — stütze dich ausschließlich auf die gegebenen Calls und Punkte.\n\n" +
      "Erkenne: (1) wiederkehrende Themen, (2) was liegen bleibt (länger offen / überfällig / teilweise), (3) wo man sich im Kreis dreht, " +
      "(4) BILANZ: was wurde vorgenommen und was ist daraus geworden — vor allem bei Zahlenzielen (Ziel/geschafft/offen). Ist etwas nicht erkennbar, leere Liste.\n" +
      "HEUTE = " + today + ".";
    const userText =
      "CALLS (neueste zuerst):\n" + (callsTxt || "(keine)") + "\n\n" +
      "OFFENE / TEILWEISE PUNKTE:\n" + (openTxt || "(keine)") + "\n\n" +
      "ERLEDIGTE PUNKTE:\n" + (doneTxt || "(keine)");
    let out: any;
    try { out = await callClaude(system, userText.slice(0, 26000), ANALYZE_TOOL, "auswertung", 3000); }
    catch (e) { return json({ error: "Die KI ist gerade nicht erreichbar: " + (e as Error).message }, 502); }
    const arr = (v: any) => Array.isArray(v) ? v : [];
    return json({
      ok: true,
      ueberblick: String(out.ueberblick || "").trim(),
      wiederkehrend: arr(out.wiederkehrend).filter((x: any) => x && x.thema).map((x: any) => ({ thema: String(x.thema).trim(), hinweis: String(x.hinweis || "").trim() })),
      liegen_geblieben: arr(out.liegen_geblieben).filter((x: any) => x && x.punkt).map((x: any) => ({ punkt: String(x.punkt).trim(), hinweis: String(x.hinweis || "").trim() })),
      im_kreis: arr(out.im_kreis).filter((x: any) => x && x.thema).map((x: any) => ({ thema: String(x.thema).trim(), hinweis: String(x.hinweis || "").trim() })),
      bilanz: arr(out.bilanz).filter((x: any) => x && x.vorgenommen).map((x: any) => ({ vorgenommen: String(x.vorgenommen).trim(), geworden: String(x.geworden || "").trim() })),
    });
  }

  return json({ error: "Unbekannter Modus." }, 400);
});
