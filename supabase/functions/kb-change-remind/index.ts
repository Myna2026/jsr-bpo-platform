// Wissensänderungen: Erinnerung an den Partner + Eskalation an uns. Nichts wird automatisch übernommen, nichts verfällt.
// - Offene Vorschläge, die 7 Tage ohne Entscheidung sind (und seit der letzten Erinnerung wieder 7 Tage): EINE Sammel-Mail
//   je Partner an die Kunden-Kontaktadressen (client_accounts contact_email / contact2_email / login_email), neutraler
//   Absender (keine Persona in der Kundenmail), Link ins Kundenportal.
// - Offene Vorschläge über 14 Tage: Befund in system_findings (Maya-Digest an den Eigentümer), einmal je Vorschlag.
// Cron stündlich; sendet nur im Zeitfenster 08-09 Uhr Berlin an Werktagen (Guard über berlinNow). body.force=true umgeht das.
// Deploy: supabase functions deploy kb-change-remind --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { smtpSend, agentMailSender } from "../_shared/agent_send.ts";
import { berlinNow, isWeekendBerlin } from "../_shared/schedule.ts";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const esc = (s: any) => String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const REMIND_DAYS = 7, ESCALATE_DAYS = 14, PORTAL = "https://client.tive360.de/";
const days = (ts: string) => Math.floor((Date.now() - new Date(ts).getTime()) / 864e5);

function mailHtml(company: string, rows: any[], docs: Record<string, string>): string {
  const KIND: Record<string, string> = { new: "Neu", update: "Änderung", delete: "Löschung" };
  const line = (c: any) => '<tr><td style="padding:8px 10px;border-top:1px solid #e5e7eb;font-size:13px;vertical-align:top;">'
    + '<div style="font-size:11px;color:#6b7280;">' + esc(KIND[c.change_kind] || c.change_kind) + (c.zielgebiet ? " · " + esc(c.zielgebiet) : "") + " · seit " + days(c.proposed_at) + " Tagen</div>"
    + '<div style="font-weight:bold;color:#0f172a;">' + esc(c.label) + "</div>"
    + (c.change_kind !== "new" ? '<div style="color:#9ca3af;text-decoration:line-through;">' + esc(c.old_value) + "</div>" : "")
    + (c.change_kind !== "delete" ? '<div style="color:#0f172a;">' + (c.change_kind === "new" ? "" : "→ ") + esc(c.new_value) + "</div>" : '<div style="color:#b91c1c;">soll entfallen</div>')
    + (c.source_document_id && docs[c.source_document_id] ? '<div style="font-size:11px;color:#6b7280;">aus „' + esc(docs[c.source_document_id]) + "“</div>" : "")
    + "</td></tr>";
  return '<!doctype html><html><head><meta charset="utf-8"></head><body style="margin:0;background:#eef2f3;font-family:Arial,Helvetica,sans-serif;">'
    + '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="padding:16px 0;"><tr><td align="center">'
    + '<table role="presentation" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#fff;border-radius:14px;overflow:hidden;">'
    + '<tr><td style="background:#0F5661;padding:18px 22px;color:#fff;"><div style="font-size:18px;font-weight:bold;">Wissensdatenbank ' + esc(company) + '</div><div style="font-size:12px;opacity:.85;">' + rows.length + ' Vorschl' + (rows.length === 1 ? "ag wartet" : "äge warten") + ' auf Ihre Bestätigung</div></td></tr>'
    + '<tr><td style="padding:16px 22px 6px;font-size:14px;line-height:1.6;color:#1f2937;">Guten Tag,<br>in Ihrer Wissensdatenbank liegen Änderungsvorschläge, die seit mindestens ' + REMIND_DAYS + ' Tagen auf eine Entscheidung warten. Bis zu Ihrer Bestätigung gilt weiterhin der bisherige Wert; nichts wird automatisch übernommen.</td></tr>'
    + '<tr><td style="padding:6px 22px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border:1px solid #e5e7eb;border-radius:10px;overflow:hidden;">' + rows.slice(0, 25).map(line).join("") + "</table>"
    + (rows.length > 25 ? '<div style="font-size:12px;color:#6b7280;padding:6px 2px;">… und ' + (rows.length - 25) + " weitere im Portal.</div>" : "") + "</td></tr>"
    + '<tr><td align="center" style="padding:14px 22px 24px;"><a href="' + PORTAL + '" style="display:inline-block;background:#0F5661;color:#fff;text-decoration:none;font-size:15px;font-weight:bold;padding:12px 22px;border-radius:9px;">Im Kundenportal prüfen</a></td></tr>'
    + '<tr><td style="padding:2px 22px 22px;font-size:11px;color:#9ca3af;line-height:1.5;">Automatische Erinnerung aus dem TIVE 360° Kundenportal. Bereich „Wissensänderungen“.</td></tr>'
    + "</table></td></tr></table></body></html>";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* Cron */ }
  const force = body.force === true, dry = body.dry === true;
  const now = berlinNow();
  if (!force && (isWeekendBerlin(now) || now.getHours() !== 8)) return json({ ok: true, skipped: "outside-window" });

  const { data: open } = await sb.from("kb_fact_changes").select("*").eq("status", "open").order("proposed_at");
  const rows = open || [];
  const out: any = { ok: true, reminded: [], escalated: 0, dry };
  const dids = [...new Set(rows.map((r: any) => r.source_document_id).filter(Boolean))];
  const docs: Record<string, string> = {};
  if (dids.length) { const { data: dd } = await sb.from("kb_documents").select("id,title").in("id", dids); for (const d of (dd || [])) docs[d.id] = d.title; }

  // 1) Erinnerung je Partner (7 Tage offen, letzte Erinnerung mind. 7 Tage her)
  const due = rows.filter((r: any) => days(r.proposed_at) >= REMIND_DAYS && (!r.reminded_at || days(r.reminded_at) >= REMIND_DAYS));
  const byProject: Record<string, any[]> = {};
  for (const r of due) (byProject[r.project_id] = byProject[r.project_id] || []).push(r);
  const sender = await agentMailSender(sb, "lena");
  for (const pid of Object.keys(byProject)) {
    const list = byProject[pid];
    const { data: accs } = await sb.from("client_accounts").select("company_name,contact_email,contact2_email,login_email,active").eq("project_id", pid);
    const to = [...new Set((accs || []).filter((a: any) => a.active !== false).flatMap((a: any) => [a.contact_email, a.contact2_email, a.login_email]).filter((e: any) => typeof e === "string" && e.includes("@")))];
    const company = (accs && accs[0] && accs[0].company_name) || pid;
    if (!to.length || !sender) { out.reminded.push({ project: pid, sent: 0, reason: !to.length ? "keine Kundenadresse" : "kein Absender" }); continue; }
    const html = mailHtml(company, list, docs);
    const subject = "Wissensdatenbank " + company + ": " + list.length + " Vorschl" + (list.length === 1 ? "ag wartet" : "äge warten") + " auf Ihre Bestätigung";
    let sent = 0;
    for (const addr of to) {
      if (dry) { sent++; continue; }
      const r = await smtpSend({ key: sender.key, email: sender.email, fromName: "TIVE 360° Wissensdatenbank" }, addr, subject, html);
      if (r.ok) sent++; else out.reminded.push({ project: pid, to: addr, error: r.error });
    }
    if (sent && !dry) await sb.from("kb_fact_changes").update({ reminded_at: new Date().toISOString() }).in("id", list.map((r: any) => r.id));
    if (sent && !dry) for (const r of list) await sb.from("kb_fact_changes").update({ reminder_count: (r.reminder_count || 0) + 1 }).eq("id", r.id);
    out.reminded.push({ project: pid, sent, to: dry ? to : undefined, changes: list.length });
  }

  // 2) Eskalation an uns (14 Tage offen), einmal je Vorschlag, als Maya-Befund (Digest an den Eigentümer)
  const esc14 = rows.filter((r: any) => days(r.proposed_at) >= ESCALATE_DAYS && !r.escalated_at);
  for (const r of esc14) {
    if (dry) { out.escalated++; continue; }
    const title = "Wissensänderung seit " + days(r.proposed_at) + " Tagen unbestätigt: " + (r.label || "") + (r.zielgebiet ? " (" + r.zielgebiet + ")" : "");
    const evidence = { project_id: r.project_id, change_id: r.id, kind: r.change_kind, old: r.old_value, new: r.new_value, proposed_at: r.proposed_at, reminders: r.reminder_count || 0 };
    try { await sb.from("system_findings").insert({ fkey: "kb_change_stale:" + r.id, category: "kb_change_stale", severity: "blocking", title, evidence }); } catch (_e) { /* fkey doppelt = schon gemeldet */ }
    await sb.from("kb_fact_changes").update({ escalated_at: new Date().toISOString() }).eq("id", r.id);
    out.escalated++;
  }
  return json(out);
});
