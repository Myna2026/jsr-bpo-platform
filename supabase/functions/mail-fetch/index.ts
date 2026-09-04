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
  const { data } = await sb.rpc("match_cv_by_email", { p_email: fromEmail });   // robust: case-insensitiv + getrimmt, nur cvs.email
  return (data as string) || null;
}
// Anhänge einer Zoho-Nachricht in den Bucket spiegeln + in mail_attachments protokollieren.
async function pullAttachments(at: string, acc: string, folderId: string, zohoMsgId: string, ourMsgId: string) {
  try {
    const info = await zget(at, "/api/accounts/" + acc + "/folders/" + folderId + "/messages/" + zohoMsgId + "/attachmentinfo");
    const d = info && info.data;
    const arr = Array.isArray(d) ? d : (d && Array.isArray(d.attachments) ? d.attachments : []);
    for (const a of arr) {
      const aid = a.attachmentId || a.attachmentPath || a.id || a.storeName;
      const name = a.attachmentName || a.fileName || a.name || "anhang";
      if (!aid) continue;
      const r = await fetch(MAIL + "/api/accounts/" + acc + "/folders/" + folderId + "/messages/" + zohoMsgId + "/attachments/" + aid, { headers: { Authorization: "Zoho-oauthtoken " + at } });
      if (!r.ok) continue;
      const bytes = new Uint8Array(await r.arrayBuffer());
      const safe = String(name).replace(/[^\w.\-]+/g, "_").slice(0, 120);
      const path = "recruiting/" + ourMsgId + "/" + safe;
      const up = await sb.storage.from("mail-attachments").upload(path, bytes, { contentType: a.contentType || a.type || "application/octet-stream", upsert: true });
      if (up.error) continue;
      await sb.from("mail_attachments").insert({ message_id: ourMsgId, direction: "in", name: String(name), size_bytes: a.size || bytes.length, mime_type: a.contentType || a.type || null, storage_path: path });
    }
  } catch (_e) { /* Anhänge optional, dürfen den Abruf nicht abbrechen */ }
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
    if (body.mode === "att_probe") {   // einmalige Strukturprüfung der Zoho-Anhang-API
      const l = await zget(at, "/api/accounts/" + acc + "/messages/view?limit=50");
      const wa = (l.data || []).find((x: any) => x.hasAttachment === true || x.hasAttachment === "1" || x.hasAttachment === 1);
      if (!wa) return json({ ok: true, note: "keine Nachricht mit Anhang im Eingang", flags: (l.data || []).slice(0, 12).map((x: any) => ({ s: x.subject, ha: x.hasAttachment })) });
      const info = await zget(at, "/api/accounts/" + acc + "/folders/" + wa.folderId + "/messages/" + wa.messageId + "/attachmentinfo");
      return json({ ok: true, msg: { subject: wa.subject, from: wa.fromAddress }, attachmentinfo: info });
    }
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
      const { data: ins } = await sb.from("mail_messages").insert({
        direction: "in", mailbox: "recruiting", cv_id: cvId,
        from_address: from, to_address: emailOf(m.toAddress || MAILBOX),
        subject: m.subject || "(kein Betreff)",
        body_html: html,
        body_text: (html ? String(html).replace(/<[^>]+>/g, " ") : String(m.summary || "")).replace(/\s+/g, " ").trim().slice(0, 4000),
        message_id: mid, status: "unread", occurred_at: occurred,
      }).select("id").maybeSingle();
      neu++; if (cvId) zugeordnet++;
      if (ins && ins.id && (m.hasAttachment === true || m.hasAttachment === "1" || m.hasAttachment === 1)) await pullAttachments(at, acc, m.folderId, m.messageId, ins.id);
    }
    return json({ ok: true, geprueft: msgs.length, neu, zugeordnet, uebersprungen: skip, eigen_ausgang: ausgang });
  } catch (e) {
    return json({ ok: false, error: (e as Error).message || String(e) }, 500);
  }
});
