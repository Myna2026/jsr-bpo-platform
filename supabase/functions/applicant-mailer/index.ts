// Bewerber-Nachrichtenversand über Zoho SMTP, Absender JE AGENT aus dem Register (ai_agents):
//   Adresse (email) + Anzeigename (mail_from_name) kommen aus der DB, das Passwort je Agent als eigenes
//   Secret ZOHO_SMTP_PASS_<KEY> (nie in der DB). So schreibt jeder Agent aus seinem eigenen Zoho-Postfach:
//   Bewerber-Mails von Clara (clara@25hrs.net), Erinnerungen von Max (max@25hrs.net).
// Modi:
//   mode:'scan'  -> Cron/Automatik: Bewerber im Trigger-Status mit Mailadresse ohne bisherigen Erfolg,
//                   Anreicherungs-Link von Clara. Nur wenn Automatik an (service role, per Cron).
//   mode:'send'  -> Manueller Einzelversand (angemeldeter management/hr-User), von Clara.
//   mode:'test'  -> Test-Mail von einem beliebigen Agenten an eine Adresse. Durch Secret MAILER_TEST_KEY
//                   geschützt (kein Login nötig), damit der Versandweg geprüft werden kann.
// Jeder Versand wird in applicant_messages protokolliert (auto|manual|test, sent|failed).
// SMTP direkt über Deno.connectTls (implizites TLS, Port 465) — schlank, ohne schwere Mail-Bibliothek
// (die sprengte am Kaltstart das Worker-Speicherlimit). Deploy: supabase functions deploy applicant-mailer --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL  = Deno.env.get("SUPABASE_URL")!;
const ANON    = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const Z_HOST  = Deno.env.get("ZOHO_SMTP_HOST") || "smtppro.zoho.eu";
const Z_PORT  = Number(Deno.env.get("ZOHO_SMTP_PORT") || "465");
const TEST_KEY = Deno.env.get("MAILER_TEST_KEY") || "";
const PUBLIC_BASE = "https://client.tive360.de";   // oeffentliche Anreicherungsseite

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

const sb = createClient(SB_URL, SERVICE);

async function loadCfg(): Promise<any> {
  const { data } = await sb.from("app_config").select("value").eq("key", "jsr_enrich_mail_v1").maybeSingle();
  return (data && data.value) || {};
}

// Absender = Agent aus dem Register. email fehlt -> nicht sendefähig (null).
async function agentSender(key: string): Promise<any | null> {
  const { data } = await sb.from("ai_agents").select("key,name,email,mail_from_name,disclosure").eq("key", key).maybeSingle();
  if (!data || !data.email) return null;
  return {
    key: data.key,
    name: data.name || key,
    email: data.email,
    fromName: data.mail_from_name || data.name || "25HRS",
    disclosure: data.disclosure || "",
  };
}
// Passwort-Secret je Agent, schreibweisen-tolerant: probiert GROSS, wie-hinterlegt und Erst-Gross-Rest-klein
// (Zoho-Secret für Paul ist z. B. ZOHO_SMTP_PASS_Paul, die anderen ...MAX/...CLARA groß).
function smtpPass(key: string): string {
  const cap = key.charAt(0).toUpperCase() + key.slice(1).toLowerCase();
  const variants = [key.toUpperCase(), key, key.toLowerCase(), cap];
  for (const v of variants) {
    const val = Deno.env.get("ZOHO_SMTP_PASS_" + v);
    if (val) return val;
  }
  return "";
}

// Anreicherungs-Einladung anlegen (wie create_cv_enrich_invite, aber direkt mit service role).
async function makeInvite(cvId: string, formId: string | null): Promise<string> {
  const token = crypto.randomUUID().replaceAll("-", "");
  const { error } = await sb.from("cv_enrich_invites").insert({ token, cv_id: cvId, form_id: formId || null, reusable: false });
  if (error) throw new Error("invite: " + error.message);
  return token;
}

function mailBody(firstName: string, link: string, sender: any): string {
  const hi = firstName ? "Hallo " + firstName + "," : "Hallo,";
  const name = sender.name || "Clara";
  const disc = sender.disclosure || "";
  return `<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#222;line-height:1.55;max-width:520px">
    <p>${hi}</p>
    <p>vielen Dank fuer deine Bewerbung. Damit wir schnell weitermachen koennen, ergaenze bitte kurz dein Profil ueber den folgenden Link. Das dauert nur wenige Minuten:</p>
    <p><a href="${link}" style="display:inline-block;padding:12px 22px;background:#0F5661;color:#fff;text-decoration:none;border-radius:8px;font-weight:700">Profil vervollstaendigen</a></p>
    <p style="font-size:13px;color:#666">Falls der Knopf nicht funktioniert, kopiere diesen Link in deinen Browser:<br>${link}</p>
    <p>Viele Gruesse<br>${name}${disc ? `<br><span style="font-size:12px;color:#888">${disc}</span>` : ""}</p>
  </div>`;
}

// UTF-8 -> Base64 sauber über TextEncoder (kein veraltetes unescape). In 0x8000-Blöcken, damit der
// Aufrufstapel bei langen Texten nicht überläuft. Ergebnis ist reiner ASCII-Base64.
function b64utf8(s: string): string {
  const bytes = new TextEncoder().encode(s);
  let bin = ""; const CH = 0x8000;
  for (let i = 0; i < bytes.length; i += CH) bin += String.fromCharCode(...bytes.subarray(i, i + CH));
  return btoa(bin);
}
// Nicht-ASCII-Kopfzeilen (z. B. "Clara · 25HRS Recruiting") RFC-2047-kodieren.
function encWord(s: string): string {
  return /[^\x00-\x7F]/.test(s) ? "=?UTF-8?B?" + b64utf8(s) + "?=" : s;
}
function buildMessage(sender: any, to: string, subject: string, html: string): string {
  const from = `${encWord(sender.fromName)} <${sender.email}>`;
  const b64 = b64utf8(html).replace(/(.{76})/g, "$1\r\n");   // 76-Zeichen-Zeilen (Vielfaches von 4 -> saubere Base64-Zeilen)
  const headers = [
    "From: " + from,
    "To: " + to,
    "Subject: " + encWord(subject),
    "MIME-Version: 1.0",
    'Content-Type: text/html; charset=utf-8',
    "Content-Transfer-Encoding: base64",
    "Date: " + new Date().toUTCString(),
    "Message-ID: <" + crypto.randomUUID() + "@25hrs.net>",
  ].join("\r\n");
  return headers + "\r\n\r\n" + b64 + "\r\n.\r\n";
}

// Versand über Zoho SMTP aus dem Postfach des Agenten, direkt gesprochen. Gibt {ok, error?} zurück (wirft nicht).
async function smtpSend(sender: any, to: string, subject: string, html: string): Promise<{ ok: boolean; error?: string }> {
  const pass = smtpPass(sender.key);
  if (!pass) return { ok: false, error: "Passwort-Secret ZOHO_SMTP_PASS_" + sender.key.toUpperCase() + " fehlt" };
  const enc = new TextEncoder(); const dec = new TextDecoder();
  let conn: Deno.TlsConn | null = null;
  try {
    conn = await Deno.connectTls({ hostname: Z_HOST, port: Z_PORT });
    const rbuf = new Uint8Array(8192);
    const read = async (): Promise<string> => {
      let acc = "";
      for (;;) {
        const n = await conn!.read(rbuf);
        if (n === null) break;
        acc += dec.decode(rbuf.subarray(0, n));
        const lines = acc.split(/\r?\n/).filter((l) => l.length);
        if (lines.length && /^\d{3} /.test(lines[lines.length - 1])) break;   // letzte Zeile = Abschluss
      }
      return acc;
    };
    const cmd = async (line: string, expect: string, label: string): Promise<void> => {
      await conn!.write(enc.encode(line + "\r\n"));
      const r = await read();
      if (!r.trimStart().startsWith(expect)) throw new Error(label + ": " + r.trim().slice(0, 200));
    };
    await read();                                             // 220 Begrüßung
    await cmd("EHLO 25hrs.net", "250", "EHLO");
    await cmd("AUTH LOGIN", "334", "AUTH");
    await cmd(btoa(sender.email), "334", "USER");
    await cmd(btoa(pass), "235", "PASS");
    await cmd("MAIL FROM:<" + sender.email + ">", "250", "MAIL FROM");
    await cmd("RCPT TO:<" + to + ">", "250", "RCPT TO");
    await cmd("DATA", "354", "DATA");
    await conn.write(enc.encode(buildMessage(sender, to, subject, html)));
    const done = await read();
    if (!done.trimStart().startsWith("250")) throw new Error("nach DATA: " + done.trim().slice(0, 200));
    try { await conn.write(enc.encode("QUIT\r\n")); } catch (_e) { /* egal */ }
    return { ok: true };
  } catch (e) {
    return { ok: false, error: "SMTP: " + ((e as Error).message || String(e)) };
  } finally {
    if (conn) { try { conn.close(); } catch (_e) { /* ignore */ } }
  }
}

// Einen Bewerber anschreiben: Einladung erzeugen, senden, protokollieren.
async function sendOne(cv: any, cfg: any, sender: any, origin: string, createdBy: string | null) {
  const token = await makeInvite(cv.id, cfg.form_id || null);
  const link = PUBLIC_BASE + "/bewerber.html?t=" + token;
  const res = await smtpSend(sender, cv.email, "Deine Bewerbung: Profil vervollstaendigen", mailBody(cv.first_name || "", link, sender));
  await sb.from("applicant_messages").insert({
    cv_id: cv.id, channel: "email", purpose: "enrich_invite", origin,
    sender_key: sender.key, to_address: cv.email, invite_token: token, form_id: cfg.form_id || null,
    status: res.ok ? "sent" : "failed", error: res.ok ? null : res.error, provider_id: null,
    created_by: createdBy, sent_at: res.ok ? new Date().toISOString() : null,
  });
  return res;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* leerer Body ok (Cron) */ }
  const mode = body.mode || "scan";
  const cfg = await loadCfg();

  // ── Test-Versand (durch MAILER_TEST_KEY geschützt) ──────────────────────────
  if (mode === "test") {
    if (!TEST_KEY || body.key !== TEST_KEY) return json({ ok: false, error: "nicht autorisiert" }, 403);
    const to = String(body.to || "").trim();
    if (!to.includes("@")) return json({ ok: false, error: "Zieladresse fehlt" }, 400);
    const sender = await agentSender(body.agent || "clara");
    if (!sender) return json({ ok: false, error: "Agent hat keine Absenderadresse im Register" });
    const html = `<div style="font-family:Arial,sans-serif;font-size:15px;color:#222;line-height:1.55">
      <p>Testnachricht vom Bewerber-Mailer.</p>
      <p>Absender: <b>${sender.fromName}</b> &lt;${sender.email}&gt; über Zoho SMTP.</p>
      <p>Wenn diese Mail ankommt, ist der Versandweg für <b>${sender.name}</b> in Betrieb.</p></div>`;
    const res = await smtpSend(sender, to, "Test: Bewerber-Mailer (" + sender.name + ")", html);
    return json({ ok: res.ok, agent: sender.key, from: sender.email, to, error: res.ok ? undefined : res.error });
  }

  // ── Automatik / Cron ────────────────────────────────────────────────────────
  if (mode === "scan") {
    if (!cfg.auto_enabled) return json({ ok: true, skipped: "auto_off" });
    const sender = await agentSender("clara");
    if (!sender) return json({ ok: true, skipped: "sender_inactive" });

    const { data: cands } = await sb.from("cvs")
      .select("id,first_name,email,status")
      .eq("status", cfg.trigger_status || "cv_accepted")
      .not("email", "is", null)
      .limit(200);

    let sent = 0, failed = 0, skipped = 0;
    for (const cv of (cands || [])) {
      if (!cv.email || !String(cv.email).includes("@")) { skipped++; continue; }
      const { data: prev } = await sb.from("applicant_messages")
        .select("id").eq("cv_id", cv.id).eq("purpose", "enrich_invite").eq("channel", "email").eq("status", "sent").limit(1);
      if (prev && prev.length) { skipped++; continue; }
      const res = await sendOne(cv, cfg, sender, "auto", null);
      res.ok ? sent++ : failed++;
    }
    return json({ ok: true, sent, failed, skipped });
  }

  // ── Manueller Einzelversand (angemeldeter management/hr-User) ────────────────
  const authz = req.headers.get("Authorization") || "";
  const userClient = createClient(SB_URL, ANON, { global: { headers: { Authorization: authz } } });
  const { data: me } = await userClient.auth.getUser();
  if (!me || !me.user) return json({ ok: false, error: "nicht angemeldet" }, 401);
  const { data: au } = await sb.from("app_users").select("role_keys,active").eq("user_id", me.user.id).maybeSingle();
  const roles: string[] = (au && au.role_keys) || [];
  if ((au && au.active === false) || !roles.some((r) => r === "management" || r === "hr")) {
    return json({ ok: false, error: "keine Berechtigung" }, 403);
  }

  const cvId = body.cv_id;
  if (!cvId) return json({ ok: false, error: "cv_id fehlt" }, 400);
  const sender = await agentSender("clara");
  if (!sender) return json({ ok: false, code: "sender_inactive", error: "Absender Clara hat keine Adresse im Register." });
  const { data: cv } = await sb.from("cvs").select("id,first_name,email,status").eq("id", cvId).maybeSingle();
  if (!cv) return json({ ok: false, error: "Bewerber nicht gefunden" });
  if (!cv.email || !String(cv.email).includes("@")) return json({ ok: false, code: "no_email", error: "Keine Mailadresse hinterlegt." });

  const res = await sendOne(cv, { ...cfg, form_id: body.form_id || cfg.form_id }, sender, "manual", me.user.id);
  return json({ ok: res.ok, error: res.ok ? undefined : res.error });
});
