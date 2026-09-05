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
const CAMPAIGN_KEY = Deno.env.get("CAMPAIGN_KEY") || "";
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

// Leitplanke: externe Mail läuft NUR über freigegebene, aktive Vorlagen (mail_templates) — kein Freitext.
async function loadTemplate(key: string): Promise<any> {
  const { data } = await sb.from("mail_templates").select("*").eq("key", key).eq("active", true).maybeSingle();
  return data || null;
}
function renderTemplate(tpl: any, vars: Record<string, string>): { subject: string; html: string } {
  const sub = (s: string) => String(s).replace(/\{\{(\w+)\}\}/g, (_m, k) => (vars[k] !== undefined ? vars[k] : ""));
  return { subject: sub(tpl.subject), html: sub(tpl.body_html) };
}
// Technische Klasse einer Aktion aus dem Register-Gate. Fail-closed: bei Fehler 'unbekannt' -> gesperrt.
async function guardClass(agent: string, action: string): Promise<string> {
  try { const { data } = await sb.rpc("agent_guard", { p_agent: agent, p_action: action }); return typeof data === "string" ? data : "unbekannt"; }
  catch (_e) { return "unbekannt"; }
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
function buildMessage(sender: any, to: string, subject: string, html: string, messageId: string): string {
  const from = `${encWord(sender.fromName)} <${sender.email}>`;
  const b64 = b64utf8(html).replace(/(.{76})/g, "$1\r\n");   // 76-Zeichen-Zeilen (Vielfaches von 4 -> saubere Base64-Zeilen)
  const headers = [
    "From: " + from,
    "To: " + to,
    "Reply-To: recruiting@25hrs.net",                        // Antworten ins Sammelpostfach (Eingang-Poll, Schnitt 2)
    "Subject: " + encWord(subject),
    "MIME-Version: 1.0",
    'Content-Type: text/html; charset=utf-8',
    "Content-Transfer-Encoding: base64",
    "Date: " + new Date().toUTCString(),
    "Message-ID: <" + messageId + ">",
  ].join("\r\n");
  return headers + "\r\n\r\n" + b64 + "\r\n.\r\n";
}

// Versand über Zoho SMTP aus dem Postfach des Agenten, direkt gesprochen. Gibt {ok, error?, messageId} zurück (wirft nicht).
async function smtpSend(sender: any, to: string, subject: string, html: string): Promise<{ ok: boolean; error?: string; messageId: string }> {
  const messageId = crypto.randomUUID() + "@25hrs.net";
  const pass = smtpPass(sender.key);
  if (!pass) return { ok: false, error: "Passwort-Secret ZOHO_SMTP_PASS_" + sender.key.toUpperCase() + " fehlt", messageId };
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
    await conn.write(enc.encode(buildMessage(sender, to, subject, html, messageId)));
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

// Einen Bewerber anschreiben: Einladung erzeugen, senden, protokollieren.
async function sendOne(cv: any, cfg: any, sender: any, origin: string, createdBy: string | null) {
  const logFail = async (err: string) => { await sb.from("applicant_messages").insert({
    cv_id: cv.id, channel: "email", purpose: "enrich_invite", origin, sender_key: sender.key,
    to_address: cv.email, form_id: cfg.form_id || null, status: "failed", error: err, created_by: createdBy });
    return { ok: false, error: err }; };
  // Leitplanke 1: externe Mail nur mit Freigabe-Klasse.
  const g = await guardClass(sender.key, "mail_external");
  if (g !== "freigabe" && g !== "autonom") return await logFail("Leitplanke: externe Mail nicht erlaubt (" + g + ")");
  // Leitplanke 2: nur freigegebene, aktive Vorlage — kein Freitext.
  const tpl = await loadTemplate("enrich_invite");
  if (!tpl) return await logFail("Keine freigegebene Vorlage (enrich_invite) aktiv");

  const token = await makeInvite(cv.id, cfg.form_id || null);
  const link = PUBLIC_BASE + "/bewerber.html?t=" + token;
  const hi = cv.first_name ? "Hallo " + cv.first_name + "," : "Hallo,";
  const { subject, html } = renderTemplate(tpl, { hi, link, name: sender.name || "Clara", disc: sender.disclosure || "" });
  const res = await smtpSend(sender, cv.email, subject, html);
  await sb.from("applicant_messages").insert({
    cv_id: cv.id, channel: "email", purpose: "enrich_invite", origin,
    sender_key: sender.key, to_address: cv.email, invite_token: token, form_id: cfg.form_id || null,
    status: res.ok ? "sent" : "failed", error: res.ok ? null : res.error, provider_id: null,
    created_by: createdBy, sent_at: res.ok ? new Date().toISOString() : null,
  });
  // Mail-Kontext-Verlauf (Schnitt 3): Ausgang mit Inhalt + Message-ID in den Bewerber-Thread schreiben.
  await sb.from("mail_messages").insert({
    direction: "out", mailbox: "recruiting", cv_id: cv.id,
    from_address: sender.email, to_address: cv.email, subject, body_html: html,
    message_id: res.messageId, status: res.ok ? "sent" : "failed", error: res.ok ? null : res.error,
  });
  return res;
}

// ── Clara-Automatik (Phasen) ─────────────────────────────────────────────────
// Offene Übergabe? Dann gehört der Bewerber Deonita -> Clara sendet NICHT (Exklusivität, kein Überschneiden).
async function hasOpenHandover(cvId: string): Promise<boolean> {
  const { data } = await sb.from("clara_handovers").select("id").eq("cv_id", cvId).is("resolved_at", null).limit(1);
  return !!(data && data.length);
}
// Werktage (Mo-Fr) seit einem ISO-Zeitpunkt, ab dem Folgetag (deckt sich mit clara_workdays_since in SQL).
function workdaysSince(iso: string | null): number {
  if (!iso) return 9999;
  const s = new Date(iso), t = new Date();
  const d = new Date(Date.UTC(s.getUTCFullYear(), s.getUTCMonth(), s.getUTCDate())); d.setUTCDate(d.getUTCDate() + 1);
  const end = new Date(Date.UTC(t.getUTCFullYear(), t.getUTCMonth(), t.getUTCDate()));
  let n = 0; while (d <= end) { const w = d.getUTCDay(); if (w >= 1 && w <= 5) n++; d.setUTCDate(d.getUTCDate() + 1); }
  return n;
}
// Phase-2-Terminlink: interview_invite direkt anlegen (Service-Rolle; die RPC ist auf angemeldete Admins gegated).
// Braucht Standard-Interviewer aus der Config; ohne die kein Link (Phase 2 sendet dann nicht).
async function createInterviewLink(cvId: string, ph2: any): Promise<string | null> {
  const parts = Array.isArray(ph2.participant_ids) ? ph2.participant_ids : [];
  if (!parts.length) return null;
  const forms = (Array.isArray(ph2.forms) && ph2.forms.length) ? ph2.forms : ["phone", "teams", "office"];
  const days = Number(ph2.expires_days) || 14;
  const token = crypto.randomUUID().replaceAll("-", "");
  const expires = new Date(Date.now() + days * 86400000).toISOString();
  const { error } = await sb.from("interview_invites").insert({ cv_id: cvId, token, participant_ids: parts, forms, status: "open", expires_at: expires });
  if (error) return null;
  return PUBLIC_BASE + "/termin.html?t=" + token;
}
// Generischer Phasen-Versand: Link ist bereits erzeugt. purpose = 'phase1'/'phase2' (+ '_reminder').
async function sendPhaseMail(cv: any, tplKey: string, link: string, sender: any, purpose: string, origin: string) {
  const tpl = await loadTemplate(tplKey);
  if (!tpl) return { ok: false, error: "Vorlage " + tplKey + " nicht aktiv" };
  const hi = cv.first_name ? "Hallo " + cv.first_name + "," : "Hallo,";
  const { subject, html } = renderTemplate(tpl, { hi, link: link || "", name: sender.name || "Clara", disc: sender.disclosure || "" });
  const res = await smtpSend(sender, cv.email, subject, html);
  await sb.from("applicant_messages").insert({ cv_id: cv.id, channel: "email", purpose, origin, sender_key: sender.key, to_address: cv.email, status: res.ok ? "sent" : "failed", error: res.ok ? null : res.error, sent_at: res.ok ? new Date().toISOString() : null });
  await sb.from("mail_messages").insert({ direction: "out", mailbox: "recruiting", cv_id: cv.id, from_address: sender.email, to_address: cv.email, subject, body_html: html, message_id: res.messageId, status: res.ok ? "sent" : "failed", error: res.ok ? null : res.error });
  return res;
}
// Eine Phase abarbeiten (Erst-Mail + Erinnerung), Besitz/Dedup/Fenster beachtet. dry = nur zählen.
async function runPhase(phaseKey: string, status: string, ph: any, sender: any, remDays: number, dry: boolean, makeLink: (cv: any) => Promise<string | null>, reactedOf: (cvId: string) => Promise<boolean>, reuseLink: (cvId: string) => Promise<string | null>) {
  const r = { sent: 0, reminded: 0, skipped: 0, failed: 0 };
  const { data: cands } = await sb.from("cvs").select("id,first_name,email,status").eq("status", status).not("email", "is", null).limit(300);
  for (const cv of (cands || [])) {
    if (!cv.email || !String(cv.email).includes("@")) { r.skipped++; continue; }
    if (await hasOpenHandover(cv.id)) { r.skipped++; continue; }   // gehört Deonita
    const { data: msgs } = await sb.from("applicant_messages").select("purpose,status,sent_at").eq("cv_id", cv.id).in("purpose", [phaseKey, phaseKey + "_reminder"]);
    const first = (msgs || []).find((m: any) => m.purpose === phaseKey && m.status === "sent");
    const remDone = (msgs || []).some((m: any) => m.purpose === phaseKey + "_reminder" && m.status === "sent");
    if (!first) {
      if (dry) { r.sent++; continue; }
      const link = await makeLink(cv);
      if (!link) { r.failed++; continue; }
      const res = await sendPhaseMail(cv, ph.template, link, sender, phaseKey, "auto");
      res.ok ? r.sent++ : r.failed++;
    } else if (!remDone && !(await reactedOf(cv.id)) && workdaysSince(first.sent_at) >= remDays) {
      if (dry) { r.reminded++; continue; }
      const link = await reuseLink(cv.id);
      const res = await sendPhaseMail(cv, ph.template, link || "", sender, phaseKey + "_reminder", "auto");
      res.ok ? r.reminded++ : r.failed++;
    } else r.skipped++;
  }
  return r;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* leerer Body ok (Cron) */ }
  const mode = body.mode || "scan";
  const cfg = await loadCfg();

  // Leitplanke: an Externe kein frei formulierter Text. Anfragen mit eigenem Body/Betreff werden abgewiesen.
  if ((mode === "scan" || mode === "send") && (body.html || body.body || body.text || body.subject || body.message)) {
    return json({ ok: false, error: "Freitext an Externe ist nicht erlaubt. Es gehen nur freigegebene Vorlagen raus." }, 400);
  }

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

  // ── Automatik / Cron (Clara-Phasen aus jsr_clara_auto_v1) ─────────────────────
  // Ersetzt den alten Einzeltrigger (cv_accepted -> enrich). Phase 1 (cv_inbound): Eingang + Vervollständigungs-
  // Link. Phase 2 (cv_confirmed): Termineinladung. Bewerber mit offener Übergabe gehören Deonita -> übersprungen.
  // body.dry:true -> nur zählen, NICHTS senden (sicheres Testen vor der Scharfschaltung).
  if (mode === "scan") {
    // Auth: der Scan versendet echt (sobald Phasen an sind) -> nur Trigger-Key ODER Service-Bearer (Cron).
    const authz = req.headers.get("Authorization") || "";
    if (!((CAMPAIGN_KEY && body.key === CAMPAIGN_KEY) || (SERVICE && authz === "Bearer " + SERVICE))) return json({ ok: false, error: "nicht autorisiert" }, 403);
    const dry = !!body.dry;
    const { data: c2 } = await sb.from("app_config").select("value").eq("key", "jsr_clara_auto_v1").maybeSingle();
    const cfg2: any = c2 && c2.value; if (!cfg2) return json({ ok: true, skipped: "no_clara_config" });
    const sender = await agentSender("clara");
    if (!sender) return json({ ok: true, skipped: "sender_inactive" });
    const g = await guardClass(sender.key, "mail_external");
    if (g !== "freigabe" && g !== "autonom") return json({ ok: false, error: "Leitplanke: externe Mail nicht erlaubt (" + g + ")" });
    const remDays = Number(cfg2.windows && cfg2.windows.reminder_workdays) || 2;
    const out: any = { ok: true, dry };

    const p1 = cfg2.phases && cfg2.phases.phase1;
    if (p1 && p1.enabled) {
      out.phase1 = await runPhase("phase1", "cv_inbound", p1, sender, remDays, dry,
        async (cv) => { const t = await makeInvite(cv.id, (cfg && cfg.form_id) || null); return PUBLIC_BASE + "/bewerber.html?t=" + t; },
        async (cvId) => { const { data } = await sb.from("cv_enrich_invites").select("used_at").eq("cv_id", cvId).order("created_at", { ascending: false }).limit(1); return !!(data && data[0] && data[0].used_at); },
        async (cvId) => { const { data } = await sb.from("cv_enrich_invites").select("token").eq("cv_id", cvId).order("created_at", { ascending: false }).limit(1); return (data && data[0]) ? PUBLIC_BASE + "/bewerber.html?t=" + data[0].token : null; });
    }
    const p2 = cfg2.phases && cfg2.phases.phase2;
    if (p2 && p2.enabled) {
      if (!(Array.isArray(p2.participant_ids) && p2.participant_ids.length)) { out.phase2 = { note: "keine Standard-Interviewer konfiguriert" }; }
      else out.phase2 = await runPhase("phase2", "cv_confirmed", p2, sender, remDays, dry,
        (cv) => createInterviewLink(cv.id, p2),
        async (cvId) => { const { data } = await sb.from("interview_invites").select("status").eq("cv_id", cvId).order("created_at", { ascending: false }).limit(1); return !!(data && data[0] && data[0].status === "booked"); },
        async (cvId) => { const { data } = await sb.from("interview_invites").select("token").eq("cv_id", cvId).order("created_at", { ascending: false }).limit(1); return (data && data[0]) ? PUBLIC_BASE + "/termin.html?t=" + data[0].token : null; });
    }
    return json(out);
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
