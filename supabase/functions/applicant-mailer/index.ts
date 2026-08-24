// Bewerber-Nachrichtenversand (Kanal-offen). Zwei Modi:
//   mode:'scan'  -> Cron/Automatik: sucht Bewerber im Trigger-Status mit Mailadresse ohne bisherigen
//                   erfolgreichen Versand und schickt jedem den Anreicherungs-Link. Nur wenn Automatik an
//                   UND Absender scharf. Kein Login noetig (service role, per Cron aufgerufen).
//   mode:'send'  -> Manueller Einzelversand aus der Bewerber-Links-Uebersicht. Braucht angemeldeten
//                   management/hr-User. Funktioniert sobald ein Absender scharf ist, unabhaengig vom
//                   Automatik-Schalter.
// Absender kommen aus mail_senders (je Marke/Projekt einer), Provider aktuell Resend (RESEND_API_KEY als
// Secret). Jeder Versand wird in applicant_messages protokolliert (auto|manual, sent|failed).
// Deploy: supabase functions deploy applicant-mailer --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL  = Deno.env.get("SUPABASE_URL")!;
const ANON    = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND  = Deno.env.get("RESEND_API_KEY") || "";
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
async function loadSender(key: string): Promise<any> {
  const { data } = await sb.from("mail_senders").select("*").eq("key", key).maybeSingle();
  return data;
}

// Anreicherungs-Einladung anlegen (wie create_cv_enrich_invite, aber direkt mit service role).
async function makeInvite(cvId: string, formId: string | null): Promise<string> {
  const token = crypto.randomUUID().replaceAll("-", "");
  const { error } = await sb.from("cv_enrich_invites").insert({ token, cv_id: cvId, form_id: formId || null, reusable: false });
  if (error) throw new Error("invite: " + error.message);
  return token;
}

function mailBody(firstName: string, link: string): string {
  const hi = firstName ? "Hallo " + firstName + "," : "Hallo,";
  return `<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#222;line-height:1.55;max-width:520px">
    <p>${hi}</p>
    <p>vielen Dank fuer deine Bewerbung. Damit wir schnell weitermachen koennen, ergaenze bitte kurz dein Profil ueber den folgenden Link. Das dauert nur wenige Minuten:</p>
    <p><a href="${link}" style="display:inline-block;padding:12px 22px;background:#0F5661;color:#fff;text-decoration:none;border-radius:8px;font-weight:700">Profil vervollstaendigen</a></p>
    <p style="font-size:13px;color:#666">Falls der Knopf nicht funktioniert, kopiere diesen Link in deinen Browser:<br>${link}</p>
    <p>Viele Gruesse<br>Dein 25HRS Team</p>
  </div>`;
}

// Versand ueber den Provider des Absenders. Gibt {ok, id?, error?} zurueck (wirft nicht).
async function providerSend(sender: any, to: string, subject: string, html: string): Promise<{ ok: boolean; id?: string; error?: string }> {
  if (sender.provider === "resend") {
    if (!RESEND) return { ok: false, error: "RESEND_API_KEY nicht gesetzt" };
    const from = sender.from_name ? `${sender.from_name} <${sender.from_email}>` : sender.from_email;
    try {
      const r = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { "Authorization": "Bearer " + RESEND, "Content-Type": "application/json" },
        body: JSON.stringify({ from, to: [to], subject, html, reply_to: sender.reply_to || undefined }),
      });
      const j = await r.json().catch(() => ({}));
      if (!r.ok) return { ok: false, error: (j && (j.message || j.name)) || ("HTTP " + r.status) };
      return { ok: true, id: j && j.id };
    } catch (e) {
      return { ok: false, error: "Netzwerkfehler: " + (e as Error).message };
    }
  }
  return { ok: false, error: "Provider '" + sender.provider + "' wird nicht unterstuetzt" };
}

// Einen Bewerber anschreiben: Einladung erzeugen, senden, protokollieren.
async function sendOne(cv: any, cfg: any, sender: any, origin: string, createdBy: string | null) {
  const token = await makeInvite(cv.id, cfg.form_id || null);
  const link = PUBLIC_BASE + "/bewerber.html?t=" + token;
  const res = await providerSend(sender, cv.email, "Deine Bewerbung: Profil vervollstaendigen", mailBody(cv.first_name || "", link));
  await sb.from("applicant_messages").insert({
    cv_id: cv.id, channel: "email", purpose: "enrich_invite", origin,
    sender_key: sender.key, to_address: cv.email, invite_token: token, form_id: cfg.form_id || null,
    status: res.ok ? "sent" : "failed", error: res.ok ? null : res.error, provider_id: res.id || null,
    created_by: createdBy, sent_at: res.ok ? new Date().toISOString() : null,
  });
  return res;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* leerer Body ok (Cron) */ }
  const mode = body.mode || "scan";
  const cfg = await loadCfg();

  // ── Automatik / Cron ────────────────────────────────────────────────────────
  if (mode === "scan") {
    if (!cfg.auto_enabled) return json({ ok: true, skipped: "auto_off" });
    const sender = await loadSender(cfg.sender_key || "25hrs");
    if (!sender || !sender.active || !sender.from_email) return json({ ok: true, skipped: "sender_inactive" });

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
  const sender = await loadSender(body.sender_key || cfg.sender_key || "25hrs");
  if (!sender) return json({ ok: false, error: "Kein Absender konfiguriert" });
  if (!sender.active || !sender.from_email) {
    return json({ ok: false, code: "sender_inactive", error: "Absender noch nicht scharf geschaltet (Adresse fehlt oder inaktiv)." });
  }
  const { data: cv } = await sb.from("cvs").select("id,first_name,email,status").eq("id", cvId).maybeSingle();
  if (!cv) return json({ ok: false, error: "Bewerber nicht gefunden" });
  if (!cv.email || !String(cv.email).includes("@")) return json({ ok: false, code: "no_email", error: "Keine Mailadresse hinterlegt." });

  const res = await sendOne(cv, { ...cfg, form_id: body.form_id || cfg.form_id }, sender, "manual", me.user.id);
  return json({ ok: res.ok, error: res.ok ? undefined : res.error });
});
