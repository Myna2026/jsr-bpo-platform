// Postfach-Eingang recruiting@25hrs.net über die Zoho Mail API (EU) in mail_messages spiegeln.
// Refresh- zu Access-Token, Eingang lesen, neue Nachrichten (dedup über Zoho messageId) als Eingang
// ablegen und automatisch dem Bewerber über die Absenderadresse zuordnen (cvs.email/better_email).
// Bewusst OHNE Ordner-Endpoint (Scope ZohoMail.folders.READ haben wir nicht): /messages/view liefert
// die Nachrichten samt folderId pro Mail; Ausgänge (Absender = unser Postfach) werden übersprungen,
// die gehen ohnehin über das System (Kampagne/Antworten) und liegen schon als 'out' in mail_messages.
// Der Thread entsteht im System über cv_id + Zeit (Antworten native im echten Postfach, Schnitt 3).
// Auth: body.key == CAMPAIGN_KEY (manuell) ODER Authorization Bearer == SERVICE_ROLE_KEY (Cron).
// Deploy: supabase functions deploy mail-fetch --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL  = Deno.env.get("SUPABASE_URL")!;
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

async function accessToken(): Promise<string> {
  const body = new URLSearchParams({ grant_type: "refresh_token", client_id: CID, client_secret: CSEC, refresh_token: RT });
  const r = await fetch(ACCOUNTS + "/oauth/v2/token", { method: "POST", body });
  const j = await r.json();
  if (!j.access_token) throw new Error("Token: " + JSON.stringify(j));
  return j.access_token;
}
async function zget(at: string, path: string): Promise<any> {
  const r = await fetch(MAIL + path, { headers: { Authorization: "Zoho-oauthtoken " + at } });
  const t = await r.text();
  try { return JSON.parse(t); } catch { return { _raw: t.slice(0, 500), _status: r.status }; }
}
async function accountId(at: string): Promise<string> {
  const acc = await zget(at, "/api/accounts");
  const a = (acc.data || []).find((x: any) => (x.primaryEmailAddress || "").toLowerCase() === MAILBOX) || (acc.data || [])[0];
  if (!a) throw new Error("kein Postfach");
  return a.accountId;
}
const emailOf = (s: string): string => { const m = String(s || "").match(/[\w.+-]+@[\w.-]+\.\w+/); return m ? m[0].toLowerCase() : ""; };

async function matchCv(fromEmail: string): Promise<string | null> {
  if (!fromEmail) return null;
  const { data } = await sb.from("cvs").select("id").or("email.ilike." + fromEmail + ",better_email.ilike." + fromEmail).limit(1);
  return data && data.length ? data[0].id : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* */ }
  const authz = req.headers.get("Authorization") || "";
  const okAuth = (CAMPAIGN_KEY && body.key === CAMPAIGN_KEY) || (SERVICE && authz === "Bearer " + SERVICE);
  if (!okAuth) return json({ ok: false, error: "nicht autorisiert" }, 403);

  try {
    const at = await accessToken();
    const acc = await accountId(at);
    const limit = Math.max(1, Math.min(100, Number(body.limit) || 50));
    const list = await zget(at, "/api/accounts/" + acc + "/messages/view?limit=" + limit);
    const msgs = list.data || [];
    let neu = 0, zugeordnet = 0, skip = 0, ausgang = 0;
    for (const m of msgs) {
      const from = emailOf(m.fromAddress || m.sender || "");
      if (from === MAILBOX) { ausgang++; continue; }                 // Eigen-Ausgang: nicht als Eingang spiegeln
      const mid = "zoho:" + m.messageId;
      const { data: exists } = await sb.from("mail_messages").select("id").eq("message_id", mid).limit(1);
      if (exists && exists.length) { skip++; continue; }
      const cvId = await matchCv(from);
      let html = "";
      try {
        const c = await zget(at, "/api/accounts/" + acc + "/folders/" + m.folderId + "/messages/" + m.messageId + "/content");
        html = (c.data && c.data.content) || "";
      } catch (_e) { /* Content optional */ }
      const occurred = m.receivedTime ? new Date(Number(m.receivedTime)).toISOString() : new Date().toISOString();
      await sb.from("mail_messages").insert({
        direction: "in", mailbox: "recruiting", cv_id: cvId,
        from_address: from, to_address: emailOf(m.toAddress || MAILBOX),
        subject: m.subject || "(kein Betreff)",
        body_html: html,
        body_text: (html ? String(html).replace(/<[^>]+>/g, " ") : String(m.summary || "")).replace(/\s+/g, " ").trim().slice(0, 4000),
        message_id: mid, status: "unread", occurred_at: occurred,
      });
      neu++; if (cvId) zugeordnet++;
    }
    return json({ ok: true, geprueft: msgs.length, neu, zugeordnet, uebersprungen: skip, eigen_ausgang: ausgang });
  } catch (e) {
    return json({ ok: false, error: (e as Error).message || String(e) }, 500);
  }
});
