// Geteilter Sales-Versand-Kern. EINE Wahrheit für Compliance + SMTP + Protokoll, genutzt von sales-send (manuell)
// und sales-followup (automatische Nachfass-Strecke). So bleibt die harte Compliance garantiert identisch.
// Absender Moritz Eckstein. Ohne Unterdrückungsprüfung, Abmeldelink UND gefülltes Impressum geht NICHTS raus.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const Z_HOST = Deno.env.get("ZOHO_SMTP_HOST") || "smtppro.zoho.eu";
const Z_PORT = Number(Deno.env.get("ZOHO_SMTP_PORT") || "465");
const FROM = "moritz.eckstein@25hrs.net";
const FROM_NAME = "Moritz Eckstein";

// Nachfass-Kette + Rhythmus (Default; überschreibbar via app_config jsr_sales_followup_v1).
const CHAIN_DEFAULT: Record<string, string | null> = { erstansprache: "nachfass1", nachfass1: "nachfass2", nachfass2: "letzter", letzter: null, reaktivierung: null };
const CADENCE_DEFAULT = { opened_days: 3, cold_days: 7 };

function b64utf8(s: string): string { const b = new TextEncoder().encode(s); let bin = ""; const CH = 0x8000; for (let i = 0; i < b.length; i += CH) bin += String.fromCharCode(...b.subarray(i, i + CH)); return btoa(bin); }
function encWord(s: string): string { return /[^\x00-\x7F]/.test(s) ? "=?UTF-8?B?" + b64utf8(s) + "?=" : s; }
function esc(s: string): string { return (s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
function fill(t: string, v: Record<string, string>): string { return (t || "").replace(/\{(\w+)\}/g, (_m, k) => (v[k] != null ? v[k] : "")); }

export async function smtpSend(pass: string, to: string, subject: string, html: string): Promise<{ ok: boolean; error?: string; messageId: string }> {
  const messageId = crypto.randomUUID() + "@25hrs.net";
  const enc = new TextEncoder(); const dec = new TextDecoder(); let conn: Deno.TlsConn | null = null;
  try {
    conn = await Deno.connectTls({ hostname: Z_HOST, port: Z_PORT }); const rbuf = new Uint8Array(8192);
    const read = async (): Promise<string> => { let acc = ""; for (;;) { const n = await conn!.read(rbuf); if (n === null) break; acc += dec.decode(rbuf.subarray(0, n)); const ls = acc.split(/\r?\n/).filter((l) => l.length); if (ls.length && /^\d{3} /.test(ls[ls.length - 1])) break; } return acc; };
    const cmd = async (line: string, expect: string, label: string) => { await conn!.write(enc.encode(line + "\r\n")); const r = await read(); if (!r.trimStart().startsWith(expect)) throw new Error(label + ": " + r.trim().slice(0, 200)); };
    const msg = ["From: " + encWord(FROM_NAME) + " <" + FROM + ">", "To: " + to, "Reply-To: " + FROM, "Subject: " + encWord(subject), "MIME-Version: 1.0", 'Content-Type: text/html; charset=utf-8', "Content-Transfer-Encoding: base64", "Date: " + new Date().toUTCString(), "Message-ID: <" + messageId + ">"].join("\r\n") + "\r\n\r\n" + b64utf8(html).replace(/(.{76})/g, "$1\r\n") + "\r\n.\r\n";
    await read(); await cmd("EHLO 25hrs.net", "250", "EHLO"); await cmd("AUTH LOGIN", "334", "AUTH");
    await cmd(btoa(FROM), "334", "USER"); await cmd(btoa(pass), "235", "PASS");
    await cmd("MAIL FROM:<" + FROM + ">", "250", "MAIL FROM"); await cmd("RCPT TO:<" + to + ">", "250", "RCPT TO"); await cmd("DATA", "354", "DATA");
    await conn.write(enc.encode(msg)); const done = await read(); if (!done.trimStart().startsWith("250")) throw new Error("nach DATA: " + done.trim().slice(0, 200));
    try { await conn.write(enc.encode("QUIT\r\n")); } catch (_e) { /* egal */ }
    return { ok: true, messageId };
  } catch (e) { return { ok: false, error: "SMTP: " + ((e as Error).message || String(e)), messageId }; }
  finally { if (conn) { try { conn.close(); } catch (_e) { /* ignore */ } } }
}

// deliverStage: eine Vorlage (mit .stage) an einen Lead senden. opts.auto markiert automatische Nachfasser.
// Rückgabe {ok,error?}. Bei Erfolg: Event geloggt, Lead-Status/Stufe/next_followup_at (verhaltensbasiert) gesetzt.
export async function deliverStage(
  sb: ReturnType<typeof createClient>,
  lead: any, tpl: any, actor: string | null, opts: { anthropic?: string; auto?: string } = {},
): Promise<{ ok: boolean; error?: string }> {
  // ── COMPLIANCE, hart. Ohne diese vier geht nichts raus. ──
  if (!lead.contact_email) return { ok: false, error: "Lead hat keine E-Mail-Adresse" };
  const { data: can } = await sb.rpc("sales_can_send", { p_email: lead.contact_email });
  if (can === false) return { ok: false, error: "Adresse ist unterdrückt (Widerspruch/Abmeldung) — kein Versand" };
  const { data: impRow } = await sb.from("app_config").select("value").eq("key", "jsr_sales_impressum_v1").maybeSingle();
  const impressum = typeof impRow?.value === "string" ? impRow.value : "";
  if (!impressum || impressum.includes("[Firmierung")) return { ok: false, error: "Impressum ist nicht gefüllt (app_config jsr_sales_impressum_v1) — kein Versand" };
  const pass = Deno.env.get("ZOHO_SMTP_PASS_MORITZ") || "";
  if (!pass) return { ok: false, error: "Secret ZOHO_SMTP_PASS_MORITZ fehlt (Postfach moritz.eckstein@25hrs.net)" };

  const stage = tpl.stage || "erstansprache";
  const firstName = (lead.contact_name || "").trim().split(/\s+/)[0] || "";
  const vars = { company: lead.company || "", name: firstName, hook: lead.hook || "", industry: lead.industry || "" };
  let bodyText = fill(tpl.body || "", vars);

  // KI-Anreicherung nur wenn eingeschaltet — personalisiert, aber keine erfundenen Fakten.
  const ANTHROPIC = opts.anthropic || "";
  if (tpl.ai_enrich && ANTHROPIC) {
    const sys = "Du bist Moritz Eckstein, VP Business Development bei 25HRS. Personalisiere den Standard-Text für diese Firma, " +
      "menschlich und konkret, auf Basis des Aufhängers/der Recherche. HARTE REGEL: keine erfundenen Firmen-Fakten, nur was " +
      "im Aufhänger/der Recherche steht. Kurz, Sie-Form, Ziel ein Telefontermin. Gib NUR den fertigen Mailtext zurück (ohne " +
      "Betreff, ohne Signatur, ohne Abmeldezeile).";
    const usr = "Firma: " + (lead.company || "?") + "\nBranche: " + (lead.industry || "?") + "\nAufhänger: " + (lead.hook || "(keiner)") +
      "\nRecherche: " + JSON.stringify(lead.research || {}) + "\n\nStandard-Text:\n" + bodyText;
    try {
      const r = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST", headers: { "x-api-key": ANTHROPIC, "anthropic-version": "2023-06-01", "content-type": "application/json" },
        body: JSON.stringify({ model: "claude-sonnet-5", max_tokens: 700, system: sys, messages: [{ role: "user", content: usr }] }),
      });
      if (r.ok) { const t = ((await r.json()).content || []).map((c: any) => c.text || "").join("").trim(); if (t) bodyText = t; }
    } catch (_e) { /* Anreicherung optional; bei Fehler Standardtext */ }
  }

  const subject = fill(tpl.subject || "", vars);
  const unsubLink = SB_URL + "/functions/v1/sales-unsubscribe?token=" + lead.unsub_token;
  const impressumLine = fill(impressum, { unsub_link: unsubLink });
  const html = '<div style="font-family:system-ui,-apple-system,Segoe UI,Arial,sans-serif;font-size:14.5px;line-height:1.6;color:#1a1a1a;max-width:600px">' +
    '<div style="white-space:pre-wrap">' + esc(bodyText) + '</div>' +
    '<div style="margin-top:18px">Beste Grüße<br>Moritz Eckstein<br><span style="color:#555">VP Business Development · 25HRS</span></div>' +
    '<div style="margin-top:22px;padding-top:10px;border-top:1px solid #e5e7eb;font-size:11px;color:#8a8a8a">' + esc(impressumLine).replace(esc(unsubLink), '<a href="' + unsubLink + '" style="color:#8a8a8a">Abmelden</a>') + '</div>' +
    '<img src="' + SB_URL + '/functions/v1/sales-track?t=' + lead.unsub_token + '" width="1" height="1" alt="" style="display:none">' +
    '</div>';

  const res = await smtpSend(pass, lead.contact_email, subject, html);
  await sb.from("sales_events").insert({ lead_id: lead.id, kind: "sent", actor, detail: { template: tpl.key, stage, variant: tpl.variant || 1, subject, message_id: res.messageId, to: lead.contact_email, ai_enrich: !!tpl.ai_enrich, auto: opts.auto || null, ok: res.ok, error: res.ok ? null : res.error } });
  if (!res.ok) return { ok: false, error: res.error };

  // Verhaltensbasierter nächster Fälligkeitszeitpunkt: hat der Lead je geöffnet → früher, sonst später.
  // Kette endet nach 'letzter' (kein next_followup mehr → Tot-Erkennung greift).
  const { data: cfgRow } = await sb.from("app_config").select("value").eq("key", "jsr_sales_followup_v1").maybeSingle();
  const cfg: any = cfgRow?.value || {};
  const chain: Record<string, string | null> = { ...CHAIN_DEFAULT, ...(cfg.chain || {}) };
  const cad = { ...CADENCE_DEFAULT, ...(cfg.cadence || {}) };
  const { data: evs } = await sb.from("sales_events").select("kind").eq("lead_id", lead.id);
  const everOpened = (evs || []).some((e: any) => e.kind === "opened" || e.kind === "replied");
  const nextStage = chain[stage];
  const upd: any = { status: "contacted", stage, last_activity_at: new Date().toISOString() };
  upd.next_followup_at = nextStage ? new Date(Date.now() + (everOpened ? cad.opened_days : cad.cold_days) * 864e5).toISOString() : null;
  await sb.from("sales_leads").update(upd).eq("id", lead.id);
  return { ok: true };
}

async function fetchSiteText(website: string): Promise<string> {
  let url = website.trim(); if (!/^https?:\/\//i.test(url)) url = "https://" + url;
  try {
    const r = await fetch(url, { headers: { "User-Agent": "Mozilla/5.0 (compatible; 25HRS-Research/1.0)" }, signal: AbortSignal.timeout(9000) });
    if (!r.ok) return "";
    let html = await r.text();
    html = html.replace(/<script[\s\S]*?<\/script>/gi, " ").replace(/<style[\s\S]*?<\/style>/gi, " ").replace(/<!--[\s\S]*?-->/g, " ");
    return html.replace(/<[^>]+>/g, " ").replace(/&[a-z]+;/gi, " ").replace(/\s+/g, " ").trim().slice(0, 9000);
  } catch (_e) { return ""; }
}

// researchLead: Firmen-Website holen, Claude leitet Aufhänger ab (keine erfundenen Fakten), Lead aktualisieren.
// Geteilt von sales-research (manuell) und sales-agent-run (autonom). Rückgabe {ok,error?,hook,hook_general}.
export async function researchLead(
  sb: ReturnType<typeof createClient>, lead: any, anthropic: string, actor: string | null,
): Promise<{ ok: boolean; error?: string; hook?: string | null; hook_general?: boolean }> {
  if (!anthropic) return { ok: false, error: "ANTHROPIC_API_KEY fehlt" };
  const siteText = lead.website ? await fetchSiteText(lead.website) : "";
  const thin = siteText.length < 200;
  const sys = "Du recherchierst für einen Vertriebs-Erstkontakt. Unser Angebot: Customer Journey mit Offshore-Standorten " +
    "im deutschsprachigen Raum (Kundenservice/Support über unsere Standorte in Kosovo und Albanien). Aus dem Website-Text " +
    "einer Firma leitest du ab: was die Firma macht, ihre Branche, und wo unser Angebot konkret passt. Formuliere EINEN " +
    "kurzen, konkreten Aufhänger (1-2 Sätze), der zeigt, dass wir uns mit der Firma beschäftigt haben — kein Einheitsbrei. " +
    "HARTE REGEL: Nur Fakten, die im Text stehen. Gibt der Text nichts her, bleibt der Aufhänger allgemein und du setzt " +
    "hook_general=true; erfinde NIEMALS Firmen-Fakten. Antworte NUR als JSON: {summary, industry, fit, hook, hook_general}.";
  const usr = thin
    ? "Es liegt kein brauchbarer Website-Text vor (Firma: " + (lead.company || "unbekannt") + "). Bleib allgemein, hook_general=true, keine erfundenen Fakten."
    : "Firma: " + (lead.company || "?") + "\n\nWebsite-Text:\n" + siteText;
  let obj: any = {};
  try {
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST", headers: { "x-api-key": anthropic, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: "claude-sonnet-5", max_tokens: 600, system: sys, messages: [{ role: "user", content: usr }] }),
    });
    if (!r.ok) return { ok: false, error: "Claude " + r.status + ": " + (await r.text()).slice(0, 160) };
    const raw = ((await r.json()).content || []).map((c: any) => c.text || "").join("");
    const m = raw.match(/\{[\s\S]*\}/); obj = m ? JSON.parse(m[0]) : {};
  } catch (e) { return { ok: false, error: "Recherche fehlgeschlagen: " + ((e as Error).message || e) }; }
  const research = { summary: obj.summary || null, industry: obj.industry || null, fit: obj.fit || null, hook_general: !!obj.hook_general, fetched: !thin, chars: siteText.length, at: new Date().toISOString() };
  const upd: Record<string, unknown> = { research, hook: obj.hook || null, status: "researched", last_activity_at: new Date().toISOString() };
  if (obj.industry && !lead.industry) upd.industry = obj.industry;
  await sb.from("sales_leads").update(upd).eq("id", lead.id);
  await sb.from("sales_events").insert({ lead_id: lead.id, kind: "research", actor, detail: { fetched: !thin, hook_general: research.hook_general, auto: actor === null ? "recherchiert" : null } });
  return { ok: true, hook: obj.hook || null, hook_general: research.hook_general };
}
