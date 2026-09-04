// Postfach-Eingang über die Zoho Mail API (EU) in mail_messages spiegeln — für ZWEI Postfächer:
//   mailbox:'recruiting' (recruiting@25hrs.net) -> Zuordnung gegen BEWERBER (cvs.email) -> cv_id
//   mailbox:'hr'         (hr@25hrs.net)         -> Zuordnung gegen MITARBEITER (employees.email/email_internal) -> employee_id
// WICHTIG hr@: hr@ ist nur ein ALIAS auf Deonitas persönlichem Postfach (deonita.bajra@). Damit KEINE private Post
// von Deonita eingesammelt wird, übernimmt der hr-Abruf NUR Mails, die an hr@25hrs.net adressiert sind (To/Cc).
// Ausgänge (Absender = unser Postfach) werden übersprungen; bei hr fällt der Ausgang ohnehin durch den To-Filter.
// Der Verlauf entsteht im System über cv_id bzw. employee_id + Zeit. Auth: body.key == CAMPAIGN_KEY ODER
// Authorization Bearer == SERVICE_ROLE_KEY (Cron). Deploy: supabase functions deploy mail-fetch --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL  = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CID = Deno.env.get("ZOHO_MAIL_CLIENT_ID") || "";
const CSEC = Deno.env.get("ZOHO_MAIL_CLIENT_SECRET") || "";
const RT_RECRUITING = Deno.env.get("ZOHO_MAIL_REFRESH_TOKEN") || "";
// hr@ wurde über einen EIGENEN Self-Client autorisiert -> eigene client_id/secret (sonst invalid_code beim Refresh).
const HR_CID = Deno.env.get("ZOHO_MAIL_HR_CLIENT_ID") || CID;
const HR_CSEC = Deno.env.get("ZOHO_MAIL_HR_CLIENT_SECRET") || CSEC;
const RT_HR = Deno.env.get("ZOHO_MAIL_HR_REFRESH_TOKEN") || "";
const CAMPAIGN_KEY = Deno.env.get("CAMPAIGN_KEY") || "";
const ACCOUNTS = "https://accounts.zoho.eu";
const MAIL = "https://mail.zoho.eu";

// Postfach-Konfiguration. link/matchRpc bestimmen, ob gegen Bewerber (cv_id) oder Mitarbeiter (employee_id)
// zugeordnet wird. recipientOnly:true (hr) -> nur an die eigene Adresse gerichtete Mails übernehmen (Alias-Schutz).
function mbConfig(key: string) {
  if (key === "hr") return { key: "hr", address: "hr@25hrs.net", rt: RT_HR, cid: HR_CID, csec: HR_CSEC, matchRpc: "match_employee_by_email", linkCol: "employee_id", recipientOnly: true };
  return { key: "recruiting", address: "recruiting@25hrs.net", rt: RT_RECRUITING, cid: CID, csec: CSEC, matchRpc: "match_cv_by_email", linkCol: "cv_id", recipientOnly: false };
}

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });
const sb = createClient(SB_URL, SERVICE);

async function accessToken(rt: string, cid: string, csec: string): Promise<string> {
  if (!rt) throw new Error("Kein Refresh-Token für dieses Postfach hinterlegt");
  const body = new URLSearchParams({ grant_type: "refresh_token", client_id: cid, client_secret: csec, refresh_token: rt });
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
// Account, auf dem die Zieladresse liegt: primär ODER als (Alias-)Adresse in emailAddress[]. Sonst der erste Account.
async function accountId(at: string, address: string): Promise<string> {
  const acc = await zget(at, "/api/accounts");
  const list = acc.data || [];
  const addr = address.toLowerCase();
  const byPrimary = list.find((x: any) => (x.primaryEmailAddress || "").toLowerCase() === addr);
  const byAlias = list.find((x: any) => (x.emailAddress || []).some((e: any) => (e.mailId || "").toLowerCase() === addr));
  const a = byPrimary || byAlias || list[0];
  if (!a) throw new Error("kein Postfach");
  return a.accountId;
}
const emailOf = (s: string): string => { const m = String(s || "").match(/[\w.+-]+@[\w.-]+\.\w+/); return m ? m[0].toLowerCase() : ""; };
// Ist die Nachricht an unsere Adresse gerichtet (To ODER Cc)? Schützt hr@ vor Deonitas Privatpost.
const addressedTo = (m: any, address: string): boolean => {
  const hay = ((m.toAddress || "") + " " + (m.ccAddress || "")).toLowerCase();
  return hay.includes(address.toLowerCase());
};

async function matchLink(rpc: string, fromEmail: string): Promise<string | null> {
  if (!fromEmail) return null;
  const { data } = await sb.rpc(rpc, { p_email: fromEmail });   // robust: case-insensitiv + getrimmt (RPC-seitig)
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

  const MB = mbConfig(String(body.mailbox || "recruiting"));

  try {
    const at = await accessToken(MB.rt, MB.cid, MB.csec);
    const acc = await accountId(at, MB.address);
    if (body.mode === "att_probe") {   // Strukturprüfung der Zoho-Anhang-API — attachmentinfo UNABHÄNGIG vom hasAttachment-Flag
      const l = await zget(at, "/api/accounts/" + acc + "/messages/view?limit=50");
      const data = l.data || [];
      const target = body.subject ? data.find((x: any) => (x.subject || "").includes(body.subject)) : (data.find((x: any) => x.hasAttachment === true || x.hasAttachment === "1" || x.hasAttachment === 1) || data[0]);
      if (!target) return json({ ok: true, note: "kein Nachricht gefunden", flags: data.slice(0, 12).map((x: any) => ({ s: x.subject, ha: x.hasAttachment })) });
      const info = await zget(at, "/api/accounts/" + acc + "/folders/" + target.folderId + "/messages/" + target.messageId + "/attachmentinfo");
      return json({ ok: true, mailbox: MB.key, account: acc, msg: { subject: target.subject, from: target.fromAddress, to: target.toAddress, hasAttachment: target.hasAttachment }, attachmentinfo: info });
    }
    const limit = Math.max(1, Math.min(100, Number(body.limit) || 50));
    const list = await zget(at, "/api/accounts/" + acc + "/messages/view?limit=" + limit);
    const msgs = list.data || [];
    if (body.mode === "dry") {   // Trockenlauf: NUR klassifizieren, NICHTS schreiben (Filter-Verifikation vor Scharfschaltung)
      const rows = msgs.map((m: any) => {
        const from = emailOf(m.fromAddress || m.sender || "");
        const uebernommen = from !== MB.address && (!MB.recipientOnly || addressedTo(m, MB.address));
        return { von: from, an: emailOf(m.toAddress || ""), betreff: (m.subject || "").slice(0, 60), uebernommen };
      });
      return json({ ok: true, mailbox: MB.key, account: acc, geprueft: msgs.length, wuerde_uebernehmen: rows.filter((r: any) => r.uebernommen).length, proben: rows.slice(0, 25) });
    }
    let neu = 0, zugeordnet = 0, skip = 0, ausgang = 0, fremd = 0;
    for (const m of msgs) {
      const from = emailOf(m.fromAddress || m.sender || "");
      if (from === MB.address) { ausgang++; continue; }              // Eigen-Ausgang: nicht als Eingang spiegeln
      // hr@ (Alias auf Deonitas Postfach): NUR an hr@ adressierte Mails übernehmen, sonst Deonitas Privatpost überspringen.
      if (MB.recipientOnly && !addressedTo(m, MB.address)) { fremd++; continue; }
      const mid = "zoho:" + m.messageId;
      const { data: exists } = await sb.from("mail_messages").select("id").eq("message_id", mid).limit(1);
      if (exists && exists.length) { skip++; continue; }
      const linkId = await matchLink(MB.matchRpc, from);
      let html = "";
      try {
        const c = await zget(at, "/api/accounts/" + acc + "/folders/" + m.folderId + "/messages/" + m.messageId + "/content");
        html = (c.data && c.data.content) || "";
      } catch (_e) { /* Content optional */ }
      const occurred = m.receivedTime ? new Date(Number(m.receivedTime)).toISOString() : new Date().toISOString();
      const row: any = {
        direction: "in", mailbox: MB.key,
        from_address: from, to_address: emailOf(m.toAddress || MB.address),
        subject: m.subject || "(kein Betreff)",
        body_html: html,
        body_text: (html ? String(html).replace(/<[^>]+>/g, " ") : String(m.summary || "")).replace(/\s+/g, " ").trim().slice(0, 4000),
        message_id: mid, status: "unread", occurred_at: occurred,
      };
      row[MB.linkCol] = linkId;   // cv_id (recruiting) ODER employee_id (hr) — reine Postfach-Zuordnung, NICHT die Akte
      const { data: ins } = await sb.from("mail_messages").insert(row).select("id").maybeSingle();
      neu++; if (linkId) zugeordnet++;
      // attachmentinfo IMMER prüfen (das hasAttachment-Flag ist unzuverlässig); pullAttachments ist bei leer folgenlos.
      if (ins && ins.id) await pullAttachments(at, acc, m.folderId, m.messageId, ins.id);
    }
    return json({ ok: true, mailbox: MB.key, geprueft: msgs.length, neu, zugeordnet, uebersprungen: skip, eigen_ausgang: ausgang, fremd_uebersprungen: fremd });
  } catch (e) {
    return json({ ok: false, mailbox: MB.key, error: (e as Error).message || String(e) }, 500);
  }
});
