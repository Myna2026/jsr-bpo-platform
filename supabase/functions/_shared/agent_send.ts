// Gemeinsame Zustellung für Agenten-Nachrichten: Zoho-SMTP (Absender je Agent aus dem Register) + Slack-DM.
// Eine Wahrheit für alle Dispatcher (Edi-Upload, Wechselkurs, Vertragsauslauf …). Layout kommt aus agent_mail.ts.
const Z_HOST = Deno.env.get("ZOHO_SMTP_HOST") || "smtppro.zoho.eu";
const Z_PORT = Number(Deno.env.get("ZOHO_SMTP_PORT") || "465");
const SLACK  = Deno.env.get("SLACK_BOT_TOKEN") || "";

export type MailSender = { key: string; email: string; fromName: string };

export async function agentMailSender(sb: any, key: string): Promise<MailSender | null> {
  const { data } = await sb.from("ai_agents").select("key,name,email,mail_from_name").eq("key", key).maybeSingle();
  return data && data.email ? { key: data.key, email: data.email, fromName: data.mail_from_name || data.name || "25HRS" } : null;
}

function b64utf8(s: string): string { const b = new TextEncoder().encode(s); let bin = ""; const CH = 0x8000; for (let i = 0; i < b.length; i += CH) bin += String.fromCharCode(...b.subarray(i, i + CH)); return btoa(bin); }
function encWord(s: string): string { return /[^\x00-\x7F]/.test(s) ? "=?UTF-8?B?" + b64utf8(s) + "?=" : s; }
function smtpPass(key: string): string { const cap = key.charAt(0).toUpperCase() + key.slice(1).toLowerCase(); for (const v of [key.toUpperCase(), key, key.toLowerCase(), cap]) { const val = Deno.env.get("ZOHO_SMTP_PASS_" + v); if (val) return val; } return ""; }
function buildMessage(sender: MailSender, to: string, subject: string, html: string): string {
  const b64 = b64utf8(html).replace(/(.{76})/g, "$1\r\n");
  const headers = ["From: " + encWord(sender.fromName) + " <" + sender.email + ">", "To: " + to, "Subject: " + encWord(subject), "MIME-Version: 1.0", "Content-Type: text/html; charset=utf-8", "Content-Transfer-Encoding: base64", "Date: " + new Date().toUTCString(), "Message-ID: <" + crypto.randomUUID() + "@25hrs.net>"].join("\r\n");
  return headers + "\r\n\r\n" + b64 + "\r\n.\r\n";
}

export async function smtpSend(sender: MailSender, to: string, subject: string, html: string): Promise<{ ok: boolean; error?: string }> {
  const pass = smtpPass(sender.key); if (!pass) return { ok: false, error: "Secret ZOHO_SMTP_PASS_" + sender.key.toUpperCase() + " fehlt" };
  const enc = new TextEncoder(), dec = new TextDecoder(); let conn: Deno.TlsConn | null = null;
  try {
    conn = await Deno.connectTls({ hostname: Z_HOST, port: Z_PORT }); const rbuf = new Uint8Array(8192);
    const read = async (): Promise<string> => { let acc = ""; for (;;) { const n = await conn!.read(rbuf); if (n === null) break; acc += dec.decode(rbuf.subarray(0, n)); const lines = acc.split(/\r?\n/).filter((l) => l.length); if (lines.length && /^\d{3} /.test(lines[lines.length - 1])) break; } return acc; };
    const cmd = async (line: string, expect: string, label: string) => { await conn!.write(enc.encode(line + "\r\n")); const r = await read(); if (!r.trimStart().startsWith(expect)) throw new Error(label + ": " + r.trim().slice(0, 200)); };
    await read(); await cmd("EHLO 25hrs.net", "250", "EHLO"); await cmd("AUTH LOGIN", "334", "AUTH");
    await cmd(btoa(sender.email), "334", "USER"); await cmd(btoa(pass), "235", "PASS");
    await cmd("MAIL FROM:<" + sender.email + ">", "250", "MAIL FROM"); await cmd("RCPT TO:<" + to + ">", "250", "RCPT TO"); await cmd("DATA", "354", "DATA");
    await conn.write(enc.encode(buildMessage(sender, to, subject, html))); const done = await read();
    if (!done.trimStart().startsWith("250")) throw new Error("nach DATA: " + done.trim().slice(0, 200));
    try { await conn.write(enc.encode("QUIT\r\n")); } catch (_e) { /* egal */ }
    return { ok: true };
  } catch (e) { return { ok: false, error: "SMTP: " + ((e as Error).message || String(e)) }; }
  finally { if (conn) { try { conn.close(); } catch (_e) { /* ignore */ } } }
}

export async function slackDM(email: string | undefined, text: string): Promise<string> {
  if (!SLACK) return "no-slack-token"; if (!email) return "no-email";
  const lu = await (await fetch("https://slack.com/api/users.lookupByEmail?email=" + encodeURIComponent(email), { headers: { Authorization: "Bearer " + SLACK } })).json();
  if (!lu.ok) return "no-slack-user";
  const o = await (await fetch("https://slack.com/api/conversations.open", { method: "POST", headers: { Authorization: "Bearer " + SLACK, "Content-Type": "application/json" }, body: JSON.stringify({ users: lu.user.id }) })).json();
  if (!o.ok) return "open-fail";
  const m = await (await fetch("https://slack.com/api/chat.postMessage", { method: "POST", headers: { Authorization: "Bearer " + SLACK, "Content-Type": "application/json" }, body: JSON.stringify({ channel: o.channel.id, text }) })).json();
  return m.ok ? "sent" : ("post:" + (m.error || "?"));
}
