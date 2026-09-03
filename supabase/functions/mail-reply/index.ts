// Antwort aus dem Postfach-Bereich über die Zoho Mail API senden (fromAddress recruiting@25hrs.net).
// Landet native im "Gesendet" des echten Postfachs (Scope ZohoMail.messages.CREATE) und wird als
// Ausgang in mail_messages protokolliert (mit cv_id, damit der Thread am Bewerber weiterläuft).
// Menschliche Antwort = Freitext ist hier erlaubt (kein Vorlagen-Zwang wie beim Automatik-Massenversand):
// es ist eine angemeldete Person, die auf EINE Konversation antwortet.
// Auth: angemeldeter management/hr-User (Browser) ODER body.key == CAMPAIGN_KEY (System/Test).
// Deploy: supabase functions deploy mail-reply --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL  = Deno.env.get("SUPABASE_URL")!;
const ANON    = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CID = Deno.env.get("ZOHO_MAIL_CLIENT_ID") || "";
const CSEC = Deno.env.get("ZOHO_MAIL_CLIENT_SECRET") || "";
const RT = Deno.env.get("ZOHO_MAIL_REFRESH_TOKEN") || "";
const CAMPAIGN_KEY = Deno.env.get("CAMPAIGN_KEY") || "";
const ACCOUNTS = "https://accounts.zoho.eu";
const MAIL = "https://mail.zoho.eu";
const MAILBOX = "recruiting@25hrs.net";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });
const sb = createClient(SB_URL, SERVICE);
const esc = (s: string) => String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const emailOf = (s: string): string => { const m = String(s || "").match(/[\w.+-]+@[\w.-]+\.\w+/); return m ? m[0].toLowerCase() : ""; };

async function accessToken(): Promise<string> {
  const body = new URLSearchParams({ grant_type: "refresh_token", client_id: CID, client_secret: CSEC, refresh_token: RT });
  const r = await fetch(ACCOUNTS + "/oauth/v2/token", { method: "POST", body });
  const j = await r.json();
  if (!j.access_token) throw new Error("Token: " + JSON.stringify(j));
  return j.access_token;
}
async function accountId(at: string): Promise<string> {
  const r = await fetch(MAIL + "/api/accounts", { headers: { Authorization: "Zoho-oauthtoken " + at } });
  const acc = await r.json();
  const a = (acc.data || []).find((x: any) => (x.primaryEmailAddress || "").toLowerCase() === MAILBOX) || (acc.data || [])[0];
  if (!a) throw new Error("kein Postfach");
  return a.accountId;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* */ }

  // Auth: Trigger-Key ODER angemeldeter management/hr-User.
  let uid: string | null = null;
  if (CAMPAIGN_KEY && body.key === CAMPAIGN_KEY) {
    uid = null;   // System/Test
  } else {
    const authz = req.headers.get("Authorization") || "";
    const userClient = createClient(SB_URL, ANON, { global: { headers: { Authorization: authz } } });
    const { data: me } = await userClient.auth.getUser();
    if (!me || !me.user) return json({ ok: false, error: "nicht angemeldet" }, 401);
    const { data: au } = await sb.from("app_users").select("role_keys,active").eq("user_id", me.user.id).maybeSingle();
    const roles: string[] = (au && au.role_keys) || [];
    if ((au && au.active === false) || !roles.some((r) => r === "management" || r === "hr")) return json({ ok: false, error: "keine Berechtigung" }, 403);
    uid = me.user.id;
  }

  const to = emailOf(body.to || "");
  if (!to) return json({ ok: false, error: "Empfänger (to) fehlt" }, 400);
  const subjectIn = String(body.subject || "").trim() || "Ihre Nachricht an 25hours Recruiting";
  const subject = /^re:/i.test(subjectIn) ? subjectIn : "Re: " + subjectIn;
  const cvId = body.cv_id || null;
  const replyTo = body.in_reply_to || null;   // mail_messages.id der eingehenden Nachricht (für Lese-Markierung)

  // Inhalt: fertiges HTML nutzen oder Klartext sauber zu HTML wandeln.
  const html = body.body_html
    ? String(body.body_html)
    : '<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:1.6;color:#1f2937;">'
      + esc(String(body.body_text || "")).replace(/\n/g, "<br>") + "</div>";

  try {
    const at = await accessToken();
    const acc = await accountId(at);
    const sendRes = await fetch(MAIL + "/api/accounts/" + acc + "/messages", {
      method: "POST",
      headers: { Authorization: "Zoho-oauthtoken " + at, "Content-Type": "application/json" },
      body: JSON.stringify({ fromAddress: MAILBOX, toAddress: to, subject, content: html, mailFormat: "html", askReceipt: "no" }),
    });
    const sj = await sendRes.json().catch(() => ({}));
    const ok = sendRes.status < 300 && (!sj.status || sj.status.code === 200 || String(sj.status?.code) === "200");
    const zid = (sj.data && (sj.data.messageId || sj.data.msgId)) || null;

    await sb.from("mail_messages").insert({
      direction: "out", mailbox: "recruiting", cv_id: cvId,
      from_address: MAILBOX, to_address: to, subject, body_html: html,
      body_text: String(body.body_text || html.replace(/<[^>]+>/g, " ")).replace(/\s+/g, " ").trim().slice(0, 4000),
      message_id: zid ? "zoho:" + zid : crypto.randomUUID() + "@25hrs.net",
      in_reply_to: replyTo, status: ok ? "sent" : "failed", error: ok ? null : JSON.stringify(sj).slice(0, 300),
    });
    // Eingehende Nachricht als beantwortet/gelesen markieren.
    if (ok && replyTo) { try { await sb.from("mail_messages").update({ status: "read" }).eq("id", replyTo); } catch (_e) { /* */ } }

    return json({ ok, to, zoho: sj.status || sj.data || null, error: ok ? undefined : "Zoho: " + JSON.stringify(sj).slice(0, 200) });
  } catch (e) {
    return json({ ok: false, error: (e as Error).message || String(e) }, 500);
  }
});
