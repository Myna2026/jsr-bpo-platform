// Sales-Akquise, Schnitt 3: Versand als Moritz. COMPLIANCE ERZWUNGEN — ohne Unterdrückungsprüfung, Abmeldelink UND
// gefülltes Impressum geht NICHTS raus. Standardtext aus sales_templates; KI reichert nur an, wenn ai_enrich=true
// (dann personalisiert, aber KEINE erfundenen Fakten). Absender moritz.eckstein@25hrs.net (Secret ZOHO_SMTP_PASS_MORITZ).
// Nur Freigabeliste. Deploy: supabase functions deploy sales-send --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC = Deno.env.get("ANTHROPIC_API_KEY") || "";
const Z_HOST = Deno.env.get("ZOHO_SMTP_HOST") || "smtppro.zoho.eu";
const Z_PORT = Number(Deno.env.get("ZOHO_SMTP_PORT") || "465");
const FROM = "moritz.eckstein@25hrs.net";
const FROM_NAME = "Moritz Eckstein";

function json(b: unknown, s = 200) { return new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } }); }
function b64utf8(s: string): string { const b = new TextEncoder().encode(s); let bin = ""; const CH = 0x8000; for (let i = 0; i < b.length; i += CH) bin += String.fromCharCode(...b.subarray(i, i + CH)); return btoa(bin); }
function encWord(s: string): string { return /[^\x00-\x7F]/.test(s) ? "=?UTF-8?B?" + b64utf8(s) + "?=" : s; }
function esc(s: string): string { return (s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
function fill(t: string, v: Record<string, string>): string { return (t || "").replace(/\{(\w+)\}/g, (_m, k) => (v[k] != null ? v[k] : "")); }

async function smtpSend(pass: string, to: string, subject: string, html: string): Promise<{ ok: boolean; error?: string; messageId: string }> {
  const messageId = crypto.randomUUID() + "@25hrs.net";
  const enc = new TextEncoder(); const dec = new TextDecoder(); let conn: Deno.TlsConn | null = null;
  try {
    conn = await Deno.connectTls({ hostname: Z_HOST, port: Z_PORT }); const rbuf = new Uint8Array(8192);
    const read = async (): Promise<string> => { let acc = ""; for (;;) { const n = await conn!.read(rbuf); if (n === null) break; acc += dec.decode(rbuf.subarray(0, n)); const ls = acc.split(/\r?\n/).filter((l) => l.length); if (ls.length && /^\d{3} /.test(ls[ls.length - 1])) break; } return acc; };
    const cmd = async (line: string, expect: string, label: string) => { await conn!.write(enc.encode(line + "\r\n")); const r = await read(); if (!r.trimStart().startsWith(expect)) throw new Error(label + ": " + r.trim().slice(0, 200)); };
    const msg = ["From: " + encWord(FROM_NAME) + " <" + FROM + ">", "To: " + to, "Reply-To: " + FROM, "Subject: " + encWord(subject), "MIME-Version: 1.0", 'Content-Type: text/html; charset=utf-8', "Content-Transfer-Encoding: base64", "Date: " + new Date().toUTCString(), "Message-ID: <" + messageId + ">"].join("\r\n") + "\r\n\r\n" + b64utf8(html).replace(/(.{76})/g, "$1\r\n") + "\r\n.\r\n";
    await read(); await cmd("EHLO 25hrs.net", "250", "EHLO"); await cmd("AUTH LOGIN", "334", "AUTH");
    await cmd(btoa(FROM), "334", "USER"); await cmd(btoa(pass), "235", "PASS");
    await cmd("MAIL FROM:<" + FROM + ">", "250", "MAIL FROM"); await cmd("RCPT TO:<" + to + ">", "250", "RCPT TO"); await cmd("DATA", "354", "DATA");
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
  const { data: acc } = await sb.from("sales_access").select("user_id").eq("user_id", u.user.id).maybeSingle();
  if (!acc) return json({ ok: false, error: "kein Zugriff" }, 403);

  const body = await req.json().catch(() => ({}));
  const { data: lead } = await sb.from("sales_leads").select("*").eq("id", body.lead_id).maybeSingle();
  if (!lead) return json({ ok: false, error: "Lead nicht gefunden" }, 404);
  const { data: tpl } = await sb.from("sales_templates").select("*").eq("key", body.template_key).eq("active", true).maybeSingle();
  if (!tpl) return json({ ok: false, error: "Keine aktive Vorlage" }, 400);

  // ── COMPLIANCE, hart. Ohne diese drei geht nichts raus. ──
  if (!lead.contact_email) return json({ ok: false, error: "Lead hat keine E-Mail-Adresse" }, 400);
  const { data: can } = await sb.rpc("sales_can_send", { p_email: lead.contact_email });
  if (can === false) return json({ ok: false, error: "Adresse ist unterdrückt (Widerspruch/Abmeldung) — kein Versand" }, 409);
  const { data: impRow } = await sb.from("app_config").select("value").eq("key", "jsr_sales_impressum_v1").maybeSingle();
  const impressum = typeof impRow?.value === "string" ? impRow.value : "";
  if (!impressum || impressum.includes("[Firmierung")) return json({ ok: false, error: "Impressum ist nicht gefüllt (app_config jsr_sales_impressum_v1) — kein Versand" }, 400);
  const pass = Deno.env.get("ZOHO_SMTP_PASS_MORITZ") || "";
  if (!pass) return json({ ok: false, error: "Secret ZOHO_SMTP_PASS_MORITZ fehlt (Postfach moritz.eckstein@25hrs.net)" }, 400);

  const firstName = (lead.contact_name || "").trim().split(/\s+/)[0] || "";
  const vars = { company: lead.company || "", name: firstName, hook: lead.hook || "", industry: lead.industry || "" };
  let bodyText = fill(tpl.body || "", vars);

  // KI-Anreicherung nur wenn eingeschaltet — personalisiert, aber keine erfundenen Fakten.
  if (tpl.ai_enrich && ANTHROPIC) {
    const sys = "Du bist Moritz Eckstein, VP Business Development bei 25HRS. Personalisiere den Standard-Text für diese Firma, " +
      "menschlich und konkret, auf Basis des Aufhängers/der Recherche. HARTE REGEL: keine erfundenen Firmen-Fakten, nur was " +
      "im Aufhänger/der Recherche steht. Kurz, Sie-Form, Ziel ein Telefontermin. Gib NUR den fertigen Mailtext zurück (ohne " +
      "Betreff, ohne Signatur, ohne Abmeldezeile).";
    const usr = "Firma: " + (lead.company || "?") + "\nBranche: " + (lead.industry || "?") + "\nAufhänger: " + (lead.hook || "(keiner)") +
      "\nRecherche: " + JSON.stringify(lead.research || {}) + "\n\nStandard-Text:\n" + bodyText;
    try {
      const r = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST", headers: { "x-api-key": ANTHROPIC, "anthropic-version": "2023-06-01", "content-type": "application/json" },
        body: JSON.stringify({ model: "claude-sonnet-5", max_tokens: 700, system: sys, messages: [{ role: "user", content: usr }] }),
      });
      if (r.ok) { const t = ((await r.json()).content || []).map((c: any) => c.text || "").join("").trim(); if (t) bodyText = t; }
    } catch (_e) { /* Anreicherung optional; bei Fehler Standardtext */ }
  }

  const subject = fill(tpl.subject || "", vars);
  const unsubLink = SB_URL + "/functions/v1/sales-unsubscribe?token=" + lead.unsub_token;
  const impressumLine = fill(impressum, { unsub_link: unsubLink });
  // Menschliche Optik: schlicht, Systemschrift, echte Signatur, dezentes Impressum/Abmelden.
  const html = '<div style="font-family:system-ui,-apple-system,Segoe UI,Arial,sans-serif;font-size:14.5px;line-height:1.6;color:#1a1a1a;max-width:600px">' +
    '<div style="white-space:pre-wrap">' + esc(bodyText) + '</div>' +
    '<div style="margin-top:18px">Beste Grüße<br>Moritz Eckstein<br><span style="color:#555">VP Business Development · 25HRS</span></div>' +
    '<div style="margin-top:22px;padding-top:10px;border-top:1px solid #e5e7eb;font-size:11px;color:#8a8a8a">' + esc(impressumLine).replace(esc(unsubLink), '<a href="' + unsubLink + '" style="color:#8a8a8a">Abmelden</a>') + '</div>' +
    '</div>';

  const res = await smtpSend(pass, lead.contact_email, subject, html);
  await sb.from("sales_events").insert({ lead_id: lead.id, kind: "sent", actor: u.user.id, detail: { template: tpl.key, subject, message_id: res.messageId, to: lead.contact_email, ai_enrich: !!tpl.ai_enrich, ok: res.ok, error: res.ok ? null : res.error } });
  if (res.ok) {
    const nf = new Date(Date.now() + 5 * 864e5).toISOString();
    await sb.from("sales_leads").update({ status: "contacted", last_activity_at: new Date().toISOString(), next_followup_at: nf }).eq("id", lead.id);
  }
  return json(res.ok ? { ok: true } : { ok: false, error: res.error }, res.ok ? 200 : 502);
});
