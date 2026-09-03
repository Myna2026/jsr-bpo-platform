// Jobmesse-Kampagne: gedrosselter Versand je Bewerber-Status über recruiting@25hrs.net.
// Absenderin FEST: Antonia Huber (echte Recruiterin, KEIN KI-Agent, kein Automatik-Hinweis).
// Passwort aus Secret ZOHO_SMTP_PASS_RECRUITING. Reply-To recruiting@25hrs.net.
//
// Leitplanke wie im übrigen System: an Externe geht NUR eine freigegebene, aktive Vorlage aus
// mail_templates (Schlüssel jobfair_<status>) raus, KEIN Freitext. Dedup + Protokoll je Bewerber
// in applicant_messages (purpose='jobfair') + Verlauf in mail_messages (mailbox 'recruiting').
//
// Drossel, weil das Postfach neu ist: pro Aufruf gedeckelt (limit) + Pause (throttle_ms) zwischen
// Mails. Der Versand wird durch die Konfig jobfair_armed (app_config) scharfgeschaltet, sonst
// laufen NUR test/status/preview. Alle Aktionen brauchen den Trigger-Key (Secret CAMPAIGN_KEY).
//
// Modi:
//   status   -> Empfänger je Status, Vorlagen-Zustand, Secret/armed-Zustand (kein Versand).
//   test     -> eine Testmail an body.to. Mit body.status = Status-Vorlage rendern (Aufbau/Ton),
//               ohne status = kurze technische Prüfmail (Versandweg des neuen Postfachs).
//   send     -> Batch für body.status: bis limit Empfänger, throttle_ms Pause dazwischen, dedup.
//               Nur wenn jobfair_armed=true und die Vorlage aktiv ist.
// Deploy: supabase functions deploy jobfair-mailer --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL  = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const Z_HOST  = Deno.env.get("ZOHO_SMTP_HOST") || "smtppro.zoho.eu";
const Z_PORT  = Number(Deno.env.get("ZOHO_SMTP_PORT") || "465");
const CAMPAIGN_KEY = Deno.env.get("CAMPAIGN_KEY") || "";
const SMTP_PASS    = Deno.env.get("ZOHO_SMTP_PASS_RECRUITING") || "";

// Absenderin fest. From-Anzeigename = "Antonia Huber" (Rolle steht in der Signatur, nicht im Header).
const SENDER = { name: "Antonia Huber", email: "recruiting@25hrs.net" };
const STATUSES = ["cv_accepted","cv_confirmed","invited","no_contact","rejected_by_employee","parking"];

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const sb = createClient(SB_URL, SERVICE);

// UTF-8 -> Base64 (blockweise, kein Stack-Überlauf bei langen Texten).
function b64utf8(s: string): string {
  const bytes = new TextEncoder().encode(s);
  let bin = ""; const CH = 0x8000;
  for (let i = 0; i < bytes.length; i += CH) bin += String.fromCharCode(...bytes.subarray(i, i + CH));
  return btoa(bin);
}
function encWord(s: string): string {
  return /[^\x00-\x7F]/.test(s) ? "=?UTF-8?B?" + b64utf8(s) + "?=" : s;
}
function buildMessage(to: string, subject: string, html: string, messageId: string): string {
  const from = `${encWord(SENDER.name)} <${SENDER.email}>`;
  const b64 = b64utf8(html).replace(/(.{76})/g, "$1\r\n");
  const headers = [
    "From: " + from,
    "To: " + to,
    "Reply-To: recruiting@25hrs.net",
    "Subject: " + encWord(subject),
    "MIME-Version: 1.0",
    'Content-Type: text/html; charset=utf-8',
    "Content-Transfer-Encoding: base64",
    "Date: " + new Date().toUTCString(),
    "Message-ID: <" + messageId + ">",
  ].join("\r\n");
  return headers + "\r\n\r\n" + b64 + "\r\n.\r\n";
}
async function smtpSend(to: string, subject: string, html: string): Promise<{ ok: boolean; error?: string; messageId: string }> {
  const messageId = crypto.randomUUID() + "@25hrs.net";
  if (!SMTP_PASS) return { ok: false, error: "Secret ZOHO_SMTP_PASS_RECRUITING fehlt", messageId };
  const enc = new TextEncoder(); const dec = new TextDecoder();
  let conn: Deno.TlsConn | null = null;
  try {
    conn = await Deno.connectTls({ hostname: Z_HOST, port: Z_PORT });
    const rbuf = new Uint8Array(8192);
    const read = async (): Promise<string> => {
      let acc = "";
      for (;;) {
        const n = await conn!.read(rbuf); if (n === null) break;
        acc += dec.decode(rbuf.subarray(0, n));
        const lines = acc.split(/\r?\n/).filter((l) => l.length);
        if (lines.length && /^\d{3} /.test(lines[lines.length - 1])) break;
      }
      return acc;
    };
    const cmd = async (line: string, expect: string, label: string): Promise<void> => {
      await conn!.write(enc.encode(line + "\r\n"));
      const r = await read();
      if (!r.trimStart().startsWith(expect)) throw new Error(label + ": " + r.trim().slice(0, 200));
    };
    await read();
    await cmd("EHLO 25hrs.net", "250", "EHLO");
    await cmd("AUTH LOGIN", "334", "AUTH");
    await cmd(btoa(SENDER.email), "334", "USER");
    await cmd(btoa(SMTP_PASS), "235", "PASS");
    await cmd("MAIL FROM:<" + SENDER.email + ">", "250", "MAIL FROM");
    await cmd("RCPT TO:<" + to + ">", "250", "RCPT TO");
    await cmd("DATA", "354", "DATA");
    await conn.write(enc.encode(buildMessage(to, subject, html, messageId)));
    const done = await read();
    if (!done.trimStart().startsWith("250")) throw new Error("nach DATA: " + done.trim().slice(0, 200));
    try { await conn.write(enc.encode("QUIT\r\n")); } catch (_e) { /* egal */ }
    return { ok: true, messageId };
  } catch (e) {
    return { ok: false, error: "SMTP: " + ((e as Error).message || String(e)), messageId };
  } finally {
    if (conn) { try { conn.close(); } catch (_e) { /* ignore */ } }
  }
}

async function loadTemplate(status: string): Promise<any | null> {
  const { data } = await sb.from("mail_templates").select("*").eq("key", "jobfair_" + status).eq("active", true).maybeSingle();
  return data || null;
}
function renderTemplate(tpl: any, vars: Record<string, string>): { subject: string; html: string } {
  const sub = (s: string) => String(s || "").replace(/\{\{(\w+)\}\}/g, (_m, k) => (vars[k] !== undefined ? vars[k] : ""));
  return { subject: sub(tpl.subject), html: sub(tpl.body_html) };
}
function varsFor(first: string): Record<string, string> {
  const f = (first || "").trim();
  return { first_name: f, name: f, hi: f ? "Përshëndetje " + f + "," : "Përshëndetje," };
}
async function isArmed(): Promise<boolean> {
  const { data } = await sb.from("app_config").select("value").eq("key", "jobfair_armed").maybeSingle();
  return !!(data && (data.value === true || (data.value && data.value.on === true)));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* */ }
  if (!CAMPAIGN_KEY || body.key !== CAMPAIGN_KEY) return json({ ok: false, error: "nicht autorisiert" }, 403);
  const mode = body.mode || "status";

  // ── Übersicht (kein Versand) ──────────────────────────────────────────────
  if (mode === "status") {
    const armed = await isArmed();
    const out: any = { ok: true, sender: SENDER, secret_present: !!SMTP_PASS, armed, statuses: {} };
    for (const st of STATUSES) {
      const { count: total } = await sb.from("cvs").select("id", { count: "exact", head: true }).eq("status", st).not("email", "is", null);
      const { data: sent } = await sb.from("applicant_messages").select("cv_id").eq("purpose", "jobfair").eq("status", "sent");
      const tpl = await loadTemplate(st);
      out.statuses[st] = { empfaenger_mit_mail: total || 0, vorlage_aktiv: !!tpl,
        betreff: tpl ? tpl.subject : null, bereits_gesendet: (sent || []).length };
    }
    return json(out);
  }

  // ── Testmail an eine Adresse ──────────────────────────────────────────────
  if (mode === "test") {
    const to = String(body.to || "").trim();
    if (!to.includes("@")) return json({ ok: false, error: "Zieladresse (to) fehlt" }, 400);
    const st = body.status;
    if (st) {
      if (!STATUSES.includes(st)) return json({ ok: false, error: "unbekannter Status" }, 400);
      const tpl = await loadTemplate(st);
      if (!tpl) return json({ ok: false, error: "Keine aktive Vorlage jobfair_" + st }, 400);
      const { subject, html } = renderTemplate(tpl, varsFor(body.sample_name || "Vorname"));
      const res = await smtpSend(to, "[TEST] " + subject, html);
      return json({ ok: res.ok, mode: "vorlage", status: st, to, error: res.ok ? undefined : res.error });
    }
    // Technische Prüfmail (Versandweg des neuen Postfachs), ohne echte Vorlage.
    const html = `<div style="font-family:Arial,sans-serif;font-size:15px;color:#222;line-height:1.55">
      <p>Technische Prüfmail der Jobmesse-Kampagne.</p>
      <p>Absenderin: <b>${SENDER.name}</b> &lt;${SENDER.email}&gt; über Zoho SMTP (Postfach recruiting@25hrs.net).</p>
      <p>Kommt diese Mail an (und nicht im Spam), ist der Versandweg des neuen Postfachs in Betrieb.
      Der Aufbau- und Ton-Test folgt mit den echten Status-Texten.</p></div>`;
    const res = await smtpSend(to, "Technische Pruefmail: recruiting@25hrs.net", html);
    return json({ ok: res.ok, mode: "technisch", to, from: SENDER.email, error: res.ok ? undefined : res.error });
  }

  // ── Batch-Versand für einen Status (gedrosselt) ───────────────────────────
  if (mode === "send") {
    if (!(await isArmed())) return json({ ok: false, error: "Kampagne nicht scharfgeschaltet (jobfair_armed)" }, 400);
    const st = body.status;
    if (!STATUSES.includes(st)) return json({ ok: false, error: "unbekannter/fehlender Status" }, 400);
    const tpl = await loadTemplate(st);
    if (!tpl) return json({ ok: false, error: "Keine aktive Vorlage jobfair_" + st }, 400);
    const limit = Math.max(1, Math.min(50, Number(body.limit) || 25));
    const throttle = Math.max(500, Math.min(15000, Number(body.throttle_ms) || 2500));

    // bereits angeschriebene cv_ids (dedup)
    const { data: done } = await sb.from("applicant_messages").select("cv_id").eq("purpose", "jobfair").eq("status", "sent");
    const seen = new Set((done || []).map((r: any) => r.cv_id));
    const { data: cands } = await sb.from("cvs").select("id,first_name,email")
      .eq("status", st).not("email", "is", null).order("created_at", { ascending: true }).limit(limit + seen.size);
    const queue = (cands || []).filter((c: any) => c.email && String(c.email).includes("@") && !seen.has(c.id)).slice(0, limit);

    let sent = 0, failed = 0;
    for (let i = 0; i < queue.length; i++) {
      const cv = queue[i];
      const { subject, html } = renderTemplate(tpl, varsFor(cv.first_name));
      const res = await smtpSend(cv.email, subject, html);
      await sb.from("applicant_messages").insert({
        cv_id: cv.id, channel: "email", purpose: "jobfair", origin: "campaign", sender_key: "recruiting",
        to_address: cv.email, status: res.ok ? "sent" : "failed", error: res.ok ? null : res.error,
        sent_at: res.ok ? new Date().toISOString() : null });
      await sb.from("mail_messages").insert({
        direction: "out", mailbox: "recruiting", cv_id: cv.id, from_address: SENDER.email, to_address: cv.email,
        subject, body_html: html, message_id: res.messageId, status: res.ok ? "sent" : "failed", error: res.ok ? null : res.error });
      res.ok ? sent++ : failed++;
      if (i < queue.length - 1) await sleep(throttle);
    }
    // Rest offen?
    const { count: total } = await sb.from("cvs").select("id", { count: "exact", head: true }).eq("status", st).not("email", "is", null);
    const remaining = Math.max(0, (total || 0) - seen.size - sent);
    return json({ ok: true, status: st, sent, failed, verbleibend: remaining, throttle_ms: throttle });
  }

  return json({ ok: false, error: "unbekannter Modus" }, 400);
});
