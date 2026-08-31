// Mail-Kontext, Schnitt 3: freie Antwort AUS DEM SAMMELPOSTFACH (recruiting@/hr@25hrs.net), im Kontext eines
// Bewerbers (cv_id) oder Mitarbeiters (employee_id). Threadet über In-Reply-To und protokolliert in mail_messages.
// KEINE persönlichen Postfächer. Absender = Sammelpostfach; Passwort je Postfach als Secret
// ZOHO_SMTP_PASS_RECRUITING / ZOHO_SMTP_PASS_HR (App-Passwort in Zoho). Bis das Secret gesetzt ist: klarer Fehler.
// Deploy: supabase functions deploy mail-send --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const Z_HOST = Deno.env.get("ZOHO_SMTP_HOST") || "smtppro.zoho.eu";
const Z_PORT = Number(Deno.env.get("ZOHO_SMTP_PORT") || "465");

const MAILBOXES: Record<string, { addr: string; secret: string; fromName: string }> = {
  recruiting: { addr: "recruiting@25hrs.net", secret: "ZOHO_SMTP_PASS_RECRUITING", fromName: "25HRS Recruiting" },
  hr:         { addr: "hr@25hrs.net",         secret: "ZOHO_SMTP_PASS_HR",         fromName: "25HRS HR" },
};
const INTERNAL = ["management", "hr", "finance", "projektleiter", "teamlead"];

function json(b: unknown, s = 200) { return new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } }); }
function b64utf8(s: string): string { const b = new TextEncoder().encode(s); let bin = ""; const CH = 0x8000; for (let i = 0; i < b.length; i += CH) bin += String.fromCharCode(...b.subarray(i, i + CH)); return btoa(bin); }
function encWord(s: string): string { return /[^\x00-\x7F]/.test(s) ? "=?UTF-8?B?" + b64utf8(s) + "?=" : s; }
function esc(s: string): string { return (s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }

function buildMessage(from: string, fromName: string, to: string, subject: string, html: string, messageId: string, inReplyTo?: string): string {
  const b64 = b64utf8(html).replace(/(.{76})/g, "$1\r\n");
  const h = [
    "From: " + encWord(fromName) + " <" + from + ">",
    "To: " + to,
    "Subject: " + encWord(subject),
    "MIME-Version: 1.0", 'Content-Type: text/html; charset=utf-8', "Content-Transfer-Encoding: base64",
    "Date: " + new Date().toUTCString(),
    "Message-ID: <" + messageId + ">",
  ];
  if (inReplyTo) { h.push("In-Reply-To: <" + inReplyTo + ">"); h.push("References: <" + inReplyTo + ">"); }
  return h.join("\r\n") + "\r\n\r\n" + b64 + "\r\n.\r\n";
}

async function smtpSend(from: string, fromName: string, pass: string, to: string, subject: string, html: string, inReplyTo?: string): Promise<{ ok: boolean; error?: string; messageId: string }> {
  const messageId = crypto.randomUUID() + "@25hrs.net";
  const enc = new TextEncoder(); const dec = new TextDecoder(); let conn: Deno.TlsConn | null = null;
  try {
    conn = await Deno.connectTls({ hostname: Z_HOST, port: Z_PORT }); const rbuf = new Uint8Array(8192);
    const read = async (): Promise<string> => { let acc = ""; for (;;) { const n = await conn!.read(rbuf); if (n === null) break; acc += dec.decode(rbuf.subarray(0, n)); const ls = acc.split(/\r?\n/).filter((l) => l.length); if (ls.length && /^\d{3} /.test(ls[ls.length - 1])) break; } return acc; };
    const cmd = async (line: string, expect: string, label: string) => { await conn!.write(enc.encode(line + "\r\n")); const r = await read(); if (!r.trimStart().startsWith(expect)) throw new Error(label + ": " + r.trim().slice(0, 200)); };
    await read(); await cmd("EHLO 25hrs.net", "250", "EHLO"); await cmd("AUTH LOGIN", "334", "AUTH");
    await cmd(btoa(from), "334", "USER"); await cmd(btoa(pass), "235", "PASS");
    await cmd("MAIL FROM:<" + from + ">", "250", "MAIL FROM"); await cmd("RCPT TO:<" + to + ">", "250", "RCPT TO"); await cmd("DATA", "354", "DATA");
    await conn.write(enc.encode(buildMessage(from, fromName, to, subject, html, messageId, inReplyTo)));
    const done = await read(); if (!done.trimStart().startsWith("250")) throw new Error("nach DATA: " + done.trim().slice(0, 200));
    try { await conn.write(enc.encode("QUIT\r\n")); } catch (_e) { /* egal */ }
    return { ok: true, messageId };
  } catch (e) { return { ok: false, error: "SMTP: " + ((e as Error).message || String(e)), messageId }; }
  finally { if (conn) { try { conn.close(); } catch (_e) { /* ignore */ } } }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false, error: "POST" }, 405);
  const sb = createClient(SB_URL, SERVICE);
  // Aufrufer prüfen: interner Zugang.
  const auth = req.headers.get("Authorization") || "";
  const { data: u } = await sb.auth.getUser(auth.replace("Bearer ", ""));
  if (!u?.user) return json({ ok: false, error: "nicht angemeldet" }, 401);
  const { data: au } = await sb.from("app_users").select("role_keys").eq("user_id", u.user.id).maybeSingle();
  const roles: string[] = au?.role_keys || [];
  if (!roles.some((r) => INTERNAL.includes(r))) return json({ ok: false, error: "keine Berechtigung" }, 403);

  const body = await req.json().catch(() => ({}));
  const { cv_id, employee_id, to, subject, body_text, in_reply_to } = body;
  const mbKey = body.mailbox === "hr" ? "hr" : "recruiting";
  const mb = MAILBOXES[mbKey];
  if (!to || !subject || !body_text) return json({ ok: false, error: "to, subject, body_text nötig" }, 400);
  const pass = Deno.env.get(mb.secret) || "";
  if (!pass) return json({ ok: false, error: "Secret " + mb.secret + " fehlt (App-Passwort des Sammelpostfachs " + mb.addr + " in Zoho anlegen)" }, 400);

  const html = "<div style=\"font-family:system-ui,Arial,sans-serif;font-size:14px;line-height:1.5;color:#111;white-space:pre-wrap\">" + esc(body_text) + "</div>";
  const res = await smtpSend(mb.addr, mb.fromName, pass, to, subject, html, in_reply_to);
  await sb.from("mail_messages").insert({
    direction: "out", mailbox: mbKey, cv_id: cv_id || null, employee_id: employee_id || null,
    from_address: mb.addr, to_address: to, subject, body_text, body_html: html,
    message_id: res.messageId, in_reply_to: in_reply_to || null,
    status: res.ok ? "sent" : "failed", error: res.ok ? null : res.error,
  });
  return json(res.ok ? { ok: true } : { ok: false, error: res.error }, res.ok ? 200 : 502);
});
