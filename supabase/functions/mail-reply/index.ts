// Antwort aus dem Postfach-Bereich über die Zoho Mail API senden — für ZWEI Postfächer:
//   mailbox:'recruiting' -> Absender recruiting@25hrs.net, Zuordnung gegen BEWERBER (cv_id)
//   mailbox:'hr'         -> Absender hr@25hrs.net (Alias auf Deonitas Account), Zuordnung gegen MITARBEITER (employee_id)
// Landet native im "Gesendet" des echten Postfachs (Scope messages.CREATE) und wird als Ausgang in mail_messages
// protokolliert (mit cv_id bzw. employee_id, damit der Verlauf am Bewerber/Mitarbeiter weiterläuft).
// Menschliche Freitext-Antwort erlaubt (angemeldete Person antwortet auf EINE Konversation).
// Auth: angemeldeter management/hr-User (Browser) ODER body.key == CAMPAIGN_KEY (System/Test).
// Deploy: supabase functions deploy mail-reply --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL  = Deno.env.get("SUPABASE_URL")!;
const ANON    = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CID = Deno.env.get("ZOHO_MAIL_CLIENT_ID") || "";
const CSEC = Deno.env.get("ZOHO_MAIL_CLIENT_SECRET") || "";
const RT_RECRUITING = Deno.env.get("ZOHO_MAIL_REFRESH_TOKEN") || "";
// hr@ über eigenen Self-Client autorisiert -> eigene client_id/secret (sonst invalid_code beim Refresh).
const HR_CID = Deno.env.get("ZOHO_MAIL_HR_CLIENT_ID") || CID;
const HR_CSEC = Deno.env.get("ZOHO_MAIL_HR_CLIENT_SECRET") || CSEC;
const RT_HR = Deno.env.get("ZOHO_MAIL_HR_REFRESH_TOKEN") || "";
const CAMPAIGN_KEY = Deno.env.get("CAMPAIGN_KEY") || "";
const ACCOUNTS = "https://accounts.zoho.eu";
const MAIL = "https://mail.zoho.eu";

function mbConfig(key: string) {
  if (key === "hr") return { key: "hr", address: "hr@25hrs.net", rt: RT_HR, cid: HR_CID, csec: HR_CSEC, matchRpc: "match_employee_by_email", linkCol: "employee_id" };
  return { key: "recruiting", address: "recruiting@25hrs.net", rt: RT_RECRUITING, cid: CID, csec: CSEC, matchRpc: "match_cv_by_email", linkCol: "cv_id" };
}

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });
const sb = createClient(SB_URL, SERVICE);
const esc = (s: string) => String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const emailOf = (s: string): string => { const m = String(s || "").match(/[\w.+-]+@[\w.-]+\.\w+/); return m ? m[0].toLowerCase() : ""; };

async function accessToken(rt: string, cid: string, csec: string): Promise<string> {
  if (!rt) throw new Error("Kein Refresh-Token für dieses Postfach hinterlegt");
  const body = new URLSearchParams({ grant_type: "refresh_token", client_id: cid, client_secret: csec, refresh_token: rt });
  const r = await fetch(ACCOUNTS + "/oauth/v2/token", { method: "POST", body });
  const j = await r.json();
  if (!j.access_token) throw new Error("Token: " + JSON.stringify(j));
  return j.access_token;
}
// Account, auf dem die Absenderadresse liegt: primär ODER als (Alias-)Adresse. Sonst der erste Account.
async function accountId(at: string, address: string): Promise<string> {
  const r = await fetch(MAIL + "/api/accounts", { headers: { Authorization: "Zoho-oauthtoken " + at } });
  const acc = await r.json();
  const list = acc.data || [];
  const addr = address.toLowerCase();
  const byPrimary = list.find((x: any) => (x.primaryEmailAddress || "").toLowerCase() === addr);
  const byAlias = list.find((x: any) => (x.emailAddress || []).some((e: any) => (e.mailId || "").toLowerCase() === addr));
  const a = byPrimary || byAlias || list[0];
  if (!a) throw new Error("kein Postfach");
  return a.accountId;
}
// Datei bei Zoho hochladen (Voraussetzung fürs Anhängen beim Senden). Gibt die Zoho-Referenz zurück.
async function zohoUploadAttachment(at: string, acc: string, name: string, bytes: Uint8Array): Promise<any | null> {
  const r = await fetch(MAIL + "/api/accounts/" + acc + "/messages/attachments?fileName=" + encodeURIComponent(name), {
    method: "POST", headers: { Authorization: "Zoho-oauthtoken " + at, "Content-Type": "application/octet-stream" }, body: bytes });
  const j = await r.json().catch(() => ({}));
  const d = j && j.data; const o = Array.isArray(d) ? d[0] : d;
  return (o && (o.storeName || o.attachmentPath)) ? { storeName: o.storeName, attachmentPath: o.attachmentPath, attachmentName: o.attachmentName || name } : null;
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

  const MB = mbConfig(String(body.mailbox || "recruiting"));

  const to = emailOf(body.to || "");
  if (!to) return json({ ok: false, error: "Empfänger (to) fehlt" }, 400);
  const subjectIn = String(body.subject || "").trim() || (MB.key === "hr" ? "Nachricht von 25hours HR" : "Nachricht von 25hours Recruiting");
  const replyTo = body.in_reply_to || null;   // mail_messages.id der eingehenden Nachricht (für Lese-Markierung)
  // "Re:" nur bei echter Antwort (in_reply_to gesetzt), NICHT bei neu verfasster Mail.
  const subject = (replyTo && !/^re:/i.test(subjectIn)) ? "Re: " + subjectIn : subjectIn;
  // Verknüpfung: vom Aufrufer (cv_id/employee_id) ODER automatisch über die Empfängeradresse.
  let linkId: string | null = body[MB.linkCol] || null;
  if (!linkId) {
    const { data: m } = await sb.rpc(MB.matchRpc, { p_email: to });   // robust: case-insensitiv + getrimmt
    if (m) linkId = m as string;
  }

  // Inhalt: fertiges HTML nutzen oder Klartext sauber zu HTML wandeln.
  const html = body.body_html
    ? String(body.body_html)
    : '<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:1.6;color:#1f2937;">'
      + esc(String(body.body_text || "")).replace(/\n/g, "<br>") + "</div>";

  try {
    const at = await accessToken(MB.rt, MB.cid, MB.csec);
    const acc = await accountId(at, MB.address);
    // Anhänge: das Frontend hat die Dateien in den Bucket 'mail-attachments' geladen und schickt die Pfade.
    const attIn: Array<{ path: string; name?: string }> = Array.isArray(body.attachments) ? body.attachments : [];
    const zohoAtts: any[] = []; const attMeta: any[] = [];
    for (const a of attIn) {
      try {
        const dl = await sb.storage.from("mail-attachments").download(a.path);
        if (dl.error || !dl.data) continue;
        const bytes = new Uint8Array(await dl.data.arrayBuffer());
        const name = a.name || String(a.path).split("/").pop() || "anhang";
        const ref = await zohoUploadAttachment(at, acc, name, bytes);
        if (ref) { zohoAtts.push(ref); attMeta.push({ path: a.path, name, size: bytes.length }); }
      } catch (_e) { /* einzelner Anhang darf den Versand nicht kippen */ }
    }
    const sendBody: any = { fromAddress: MB.address, toAddress: to, subject, content: html, mailFormat: "html", askReceipt: "no" };
    if (zohoAtts.length) sendBody.attachments = zohoAtts;
    const sendRes = await fetch(MAIL + "/api/accounts/" + acc + "/messages", {
      method: "POST",
      headers: { Authorization: "Zoho-oauthtoken " + at, "Content-Type": "application/json" },
      body: JSON.stringify(sendBody),
    });
    const sj = await sendRes.json().catch(() => ({}));
    const ok = sendRes.status < 300 && (!sj.status || sj.status.code === 200 || String(sj.status?.code) === "200");
    const zid = (sj.data && (sj.data.messageId || sj.data.msgId)) || null;

    const outRow: any = {
      direction: "out", mailbox: MB.key,
      from_address: MB.address, to_address: to, subject, body_html: html,
      body_text: String(body.body_text || html.replace(/<[^>]+>/g, " ")).replace(/\s+/g, " ").trim().slice(0, 4000),
      message_id: zid ? "zoho:" + zid : crypto.randomUUID() + "@25hrs.net",
      in_reply_to: replyTo, status: ok ? "sent" : "failed", error: ok ? null : JSON.stringify(sj).slice(0, 300),
    };
    outRow[MB.linkCol] = linkId;
    const { data: outMsg } = await sb.from("mail_messages").insert(outRow).select("id").maybeSingle();
    // Gesendete Anhänge protokollieren (im Verlauf/Gesendet herunterladbar).
    if (ok && outMsg && outMsg.id && attMeta.length) {
      for (const a of attMeta) { try { await sb.from("mail_attachments").insert({ message_id: outMsg.id, direction: "out", name: a.name, size_bytes: a.size, storage_path: a.path }); } catch (_e) { /* */ } }
    }
    // Eingehende Nachricht als beantwortet/gelesen markieren.
    if (ok && replyTo) { try { await sb.from("mail_messages").update({ status: "read" }).eq("id", replyTo); } catch (_e) { /* */ } }

    return json({ ok, mailbox: MB.key, to, angehaengt: zohoAtts.length, zoho: sj.status || sj.data || null, error: ok ? undefined : "Zoho: " + JSON.stringify(sj).slice(0, 200) });
  } catch (e) {
    return json({ ok: false, mailbox: MB.key, error: (e as Error).message || String(e) }, 500);
  }
});
