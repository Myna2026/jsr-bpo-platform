// Agenten Round 3, Schnitt 1: Handlung aus der Meldung AUSFÜHREN (auf Bestätigung). Streng in den Guardrails:
// nur Katalog-Aktionen (kein Freitext), interne getemplate Aufforderungen an EIGENE Leute (Mail ok), keine freien
// Außen-Mails, keine Entscheidungen. Zielmenge wird mit perm() des BESTÄTIGENDEN geschnitten (RPC). Protokoll in
// agent_action_log + mail_messages; Insight wird als 'acted' markiert. Deploy: supabase functions deploy agent-act --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const Z_HOST = Deno.env.get("ZOHO_SMTP_HOST") || "smtppro.zoho.eu";
const Z_PORT = Number(Deno.env.get("ZOHO_SMTP_PORT") || "465");
const HR_ADDR = "hr@25hrs.net";
const INTERNAL = ["management", "hr", "finance", "projektleiter", "teamlead"];

// Katalog: nur diese Aktionen. Jede kennt ihre Ziel-RPC + interne Vorlage (kein Freitext).
const CATALOG: Record<string, { targets: string; subject: string; body: (name: string) => string }> = {
  remind_missing_bank: {
    targets: "agent_missing_bank_targets",
    subject: "Bitte Bankverbindung nachtragen",
    body: (name) => `Hallo ${name || ""},\n\nfür die Lohnzahlung fehlt uns noch deine Bankverbindung. Bitte trag sie in deinem Mitarbeiter-Portal nach oder gib sie der Personalabteilung.\n\nDanke dir!\nDein HR-Team, 25HRS`,
  },
};

function json(b: unknown, s = 200) { return new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } }); }
function b64utf8(s: string): string { const b = new TextEncoder().encode(s); let bin = ""; const CH = 0x8000; for (let i = 0; i < b.length; i += CH) bin += String.fromCharCode(...b.subarray(i, i + CH)); return btoa(bin); }
function encWord(s: string): string { return /[^\x00-\x7F]/.test(s) ? "=?UTF-8?B?" + b64utf8(s) + "?=" : s; }
function esc(s: string): string { return (s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }

async function smtpSend(pass: string, to: string, subject: string, html: string): Promise<{ ok: boolean; error?: string; messageId: string }> {
  const messageId = crypto.randomUUID() + "@25hrs.net";
  const enc = new TextEncoder(); const dec = new TextDecoder(); let conn: Deno.TlsConn | null = null;
  try {
    conn = await Deno.connectTls({ hostname: Z_HOST, port: Z_PORT }); const rbuf = new Uint8Array(8192);
    const read = async (): Promise<string> => { let acc = ""; for (;;) { const n = await conn!.read(rbuf); if (n === null) break; acc += dec.decode(rbuf.subarray(0, n)); const ls = acc.split(/\r?\n/).filter((l) => l.length); if (ls.length && /^\d{3} /.test(ls[ls.length - 1])) break; } return acc; };
    const cmd = async (line: string, expect: string, label: string) => { await conn!.write(enc.encode(line + "\r\n")); const r = await read(); if (!r.trimStart().startsWith(expect)) throw new Error(label + ": " + r.trim().slice(0, 200)); };
    const msg = ["From: 25HRS HR <" + HR_ADDR + ">", "To: " + to, "Subject: " + encWord(subject), "MIME-Version: 1.0", 'Content-Type: text/html; charset=utf-8', "Content-Transfer-Encoding: base64", "Date: " + new Date().toUTCString(), "Message-ID: <" + messageId + ">"].join("\r\n") + "\r\n\r\n" + b64utf8(html).replace(/(.{76})/g, "$1\r\n") + "\r\n.\r\n";
    await read(); await cmd("EHLO 25hrs.net", "250", "EHLO"); await cmd("AUTH LOGIN", "334", "AUTH");
    await cmd(btoa(HR_ADDR), "334", "USER"); await cmd(btoa(pass), "235", "PASS");
    await cmd("MAIL FROM:<" + HR_ADDR + ">", "250", "MAIL FROM"); await cmd("RCPT TO:<" + to + ">", "250", "RCPT TO"); await cmd("DATA", "354", "DATA");
    await conn.write(enc.encode(msg)); const done = await read(); if (!done.trimStart().startsWith("250")) throw new Error("nach DATA: " + done.trim().slice(0, 200));
    try { await conn.write(enc.encode("QUIT\r\n")); } catch (_e) { /* egal */ }
    return { ok: true, messageId };
  } catch (e) { return { ok: false, error: "SMTP: " + ((e as Error).message || String(e)), messageId }; }
  finally { if (conn) { try { conn.close(); } catch (_e) { /* ignore */ } } }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false, error: "POST" }, 405);
  const sb = createClient(SB_URL, SERVICE);
  const { data: u } = await sb.auth.getUser((req.headers.get("Authorization") || "").replace("Bearer ", ""));
  if (!u?.user) return json({ ok: false, error: "nicht angemeldet" }, 401);
  const { data: au } = await sb.from("app_users").select("role_keys").eq("user_id", u.user.id).maybeSingle();
  if (!(au?.role_keys || []).some((r: string) => INTERNAL.includes(r))) return json({ ok: false, error: "keine Berechtigung" }, 403);

  const body = await req.json().catch(() => ({}));
  const insightId = body.insight_id;
  if (!insightId) return json({ ok: false, error: "insight_id fehlt" }, 400);

  // Insight laden + prüfen: gehört dem Bestätigenden, hat eine Katalog-Aktion, noch nicht ausgeführt.
  const { data: ins } = await sb.from("agent_insights").select("id,user_id,action,acted_at").eq("id", insightId).maybeSingle();
  if (!ins) return json({ ok: false, error: "Meldung nicht gefunden" }, 404);
  if (ins.user_id !== u.user.id) return json({ ok: false, error: "nicht deine Meldung" }, 403);
  if (ins.acted_at) return json({ ok: false, error: "bereits ausgeführt" }, 409);
  const actKey = ins.action?.key;
  const spec = actKey ? CATALOG[actKey] : null;
  if (!spec) return json({ ok: false, error: "keine erlaubte Aktion an dieser Meldung" }, 400);

  const pass = Deno.env.get("ZOHO_SMTP_PASS_HR") || "";
  if (!pass) return json({ ok: false, error: "Secret ZOHO_SMTP_PASS_HR fehlt (App-Passwort des Sammelpostfachs " + HR_ADDR + ")" }, 400);

  // Zielmenge, perm-gescopt auf den Bestätigenden.
  const { data: targets } = await sb.rpc(spec.targets, { p_actor: u.user.id });
  const list = (targets || []) as { employee_id: string; email: string; first_name: string }[];
  let sent = 0; const fails: string[] = [];
  for (const t of list) {
    const html = "<div style=\"font-family:system-ui,Arial,sans-serif;font-size:14px;line-height:1.55;color:#111;white-space:pre-wrap\">" + esc(spec.body(t.first_name)) + "</div>";
    const res = await smtpSend(pass, t.email, spec.subject, html);
    await sb.from("mail_messages").insert({ direction: "out", mailbox: "hr", employee_id: t.employee_id, from_address: HR_ADDR, to_address: t.email, subject: spec.subject, body_html: html, message_id: res.messageId, status: res.ok ? "sent" : "failed", error: res.ok ? null : res.error });
    if (res.ok) sent++; else fails.push(t.email);
  }
  await sb.from("agent_action_log").insert({ insight_id: insightId, action_key: actKey, actor: u.user.id, target_count: sent, detail: { total: list.length, fails } });
  await sb.from("agent_insights").update({ acted_at: new Date().toISOString() }).eq("id", insightId);
  return json({ ok: true, sent, total: list.length, fails });
});
