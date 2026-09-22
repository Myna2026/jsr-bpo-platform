// Kalender-Erinnerung: 15 Minuten vor einem Termin eine Nachricht an alle Teilnehmer, per Mail (Layout der Agenten-Mails)
// und Slack. Inhalt: Was, wann, wo und der Teams-Link, falls hinterlegt. Jeder kann sie für sich abschalten
// (calendar_reminder_prefs.enabled=false, Schalter im HR-Kalender). Läuft alle 5 Minuten per Cron.
// Doppelversand ausgeschlossen: der Anspruch wird VOR dem Senden geschrieben (calendar_reminders_sent, Unique je
// Termin+Tag+Person) — dieselbe Falle wie beim Erinnerungs-Dispatcher.
// Test: {"dry":true} zeigt Empfänger und Mail-HTML ohne Versand; {"preview_to":"mail@…"} schickt eine Probe.
// Deploy: supabase functions deploy calendar-reminder --use-api --no-verify-jwt
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { agentBrand, shell, lead, button, linkGoto, callout } from "../_shared/agent_mail.ts";
import { smtpSend, slackDM, agentMailSender } from "../_shared/agent_send.ts";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const LEAD_MIN = 15;            // Vorlauf
const WINDOW_MIN = 6;           // Fenster um die 15 Minuten (Cron alle 5 Minuten, damit nichts durchrutscht)
const berlin = () => new Date(new Date().toLocaleString("en-US", { timeZone: "Europe/Berlin" }));
const iso = (d: Date) => d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
const hhmm = (t: string) => String(t || "").slice(0, 5);
const deDate = (s: string) => { const [y, m, d] = String(s).split("-"); return d + "." + m + "." + y; };

// Fällt der Termin heute an? Einzeltermin, wöchentlich (gleicher Wochentag) oder monatlich (gleicher Tag im Monat).
function occursToday(ev: any, today: Date): boolean {
  const d0 = new Date(String(ev.start_date) + "T00:00:00");
  const t0 = new Date(iso(today) + "T00:00:00");
  if (t0 < d0) return false;
  if (ev.until_date && iso(today) > String(ev.until_date)) return false;
  const rec = String(ev.recurrence || "none");
  if (rec === "none" || !rec) return iso(today) === String(ev.start_date);
  if (rec === "weekly") return d0.getDay() === t0.getDay();
  if (rec === "monthly") return d0.getDate() === t0.getDate();
  return iso(today) === String(ev.start_date);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* Cron */ }
  const dry = body.dry === true;
  const previewTo = (typeof body.preview_to === "string" && body.preview_to.includes("@")) ? body.preview_to : null;
  const now = berlin();
  const today = iso(now);
  const nowMin = now.getHours() * 60 + now.getMinutes();

  const { data: evs } = await sb.from("calendar_events").select("id,title,description,location,start_date,start_time,end_time,recurrence,until_date,participants,meeting_url,project_id,kind");
  const due: any[] = [];
  for (const ev of (evs || [])) {
    if (!ev.start_time) continue;                                  // ohne Uhrzeit keine Erinnerung
    if (!(ev.participants && ev.participants.length)) continue;     // ohne Teilnehmer niemanden zu erinnern
    if (!occursToday(ev, now)) continue;
    const [h, m] = hhmm(ev.start_time).split(":").map(Number);
    const diff = (h * 60 + m) - nowMin;                             // Minuten bis zum Start
    if (previewTo || dry ? diff > -600 : (diff <= LEAD_MIN && diff > LEAD_MIN - WINDOW_MIN)) due.push({ ...ev, minutes_to: diff });
  }
  // Trockenlauf/Probe: den NÄCHSTEN anstehenden Termin zeigen (vergangene zuletzt), im Echtbetrieb spielt die Reihenfolge keine Rolle
  due.sort((a, b) => ((a.minutes_to < 0 ? 9999 : a.minutes_to) - (b.minutes_to < 0 ? 9999 : b.minutes_to)));
  if (previewTo || dry) due.splice(1);                              // Probe/Trockenlauf: nur der nächste Termin

  if (!due.length) return json({ ok: true, checked: (evs || []).length, due: 0 });

  // Teilnehmer auflösen (Mitarbeiter → Mail) und Abschaltungen lesen
  const ids = [...new Set(due.flatMap((e: any) => e.participants))];
  const { data: emps } = await sb.from("employees").select("id,first_name,last_name,email,email_internal").in("id", ids);
  const empBy: Record<string, any> = {}; for (const e of (emps || [])) empBy[e.id] = e;
  const { data: prefs } = await sb.from("calendar_reminder_prefs").select("employee_id,enabled").in("employee_id", ids);
  const off = new Set((prefs || []).filter((p: any) => p.enabled === false).map((p: any) => p.employee_id));
  const { data: projs } = await sb.from("projects").select("id,name"); const projName: Record<string, string> = {}; for (const p of (projs || [])) projName[p.id] = p.name;

  const brand = await agentBrand(sb, "max", "#2563eb");             // Max erinnert an Termine und Aufgaben
  const sender = await agentMailSender(sb, "max");
  const results: any[] = []; let previewHtml = "";

  for (const ev of due) {
    const start = hhmm(ev.start_time), end = ev.end_time ? hhmm(ev.end_time) : "";
    const wann = deDate(ev.start_date === today || !ev.recurrence || ev.recurrence === "none" ? today : today) + ", " + start + (end ? " bis " + end : "") + " Uhr";
    const note = String(ev.description || "").trim();
    const place = String(ev.location || "").trim();
    const online = !!ev.meeting_url;
    const whereTxt = online ? ("Online (Microsoft Teams)" + (place ? " · " + place : "")) : (place || "");
    const rows: string[] = [];
    rows.push('<tr><td style="padding:4px 0;width:92px;color:#6b7280;font-size:13px;">Wann</td><td style="padding:4px 0;font-size:15px;font-weight:bold;color:#111827;">' + wann + "</td></tr>");
    if (whereTxt) rows.push('<tr><td style="padding:4px 0;color:#6b7280;font-size:13px;">Wo</td><td style="padding:4px 0;font-size:15px;color:#111827;">' + whereTxt.replace(/</g, "&lt;").slice(0, 140) + "</td></tr>");
    if (ev.project_id && projName[ev.project_id]) rows.push('<tr><td style="padding:4px 0;color:#6b7280;font-size:13px;">Projekt</td><td style="padding:4px 0;font-size:15px;color:#111827;">' + projName[ev.project_id] + "</td></tr>");
    const inner = lead(ev.minutes_to >= 1 ? ("In <b>" + Math.round(ev.minutes_to) + " Minuten</b> geht es los.") : "Es geht gleich los.")
      + '<tr><td style="padding:6px 22px 2px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f7f9fb;border-radius:12px;padding:12px 14px;"><tr><td><table role="presentation" width="100%" cellpadding="0" cellspacing="0">'
      + rows.join("") + "</table></td></tr></table></td></tr>"
      + (online ? button(ev.meeting_url, "Teams-Meeting öffnen", brand.accent) : "")
      + (note ? callout("Notiz", note.replace(/</g, "&lt;").slice(0, 400), brand.accent) : "")
      + button(linkGoto("calendar"), "Zum Kalender", "#6b7280");
    const html = shell(brand, String(ev.title || "Termin"), "Erinnerung · 15 Minuten vorher", inner);
    const subject = (ev.minutes_to >= 1 ? "In " + Math.round(ev.minutes_to) + " Minuten: " : "Gleich: ") + String(ev.title || "Termin");
    const slackTxt = "*" + String(ev.title || "Termin") + "*\n" + (ev.minutes_to >= 1 ? "In " + Math.round(ev.minutes_to) + " Minuten" : "Gleich") + " · " + wann
      + (whereTxt ? "\n" + whereTxt : "") + (online ? "\n" + ev.meeting_url : "") + (note ? "\n" + note.split("\n")[0].slice(0, 140) : "");
    if (previewTo) {
      previewHtml = html;
      const mr = sender ? await smtpSend(sender, previewTo, "[Probe] " + subject, html) : { ok: false, error: "kein Absender" };
      return json({ ok: true, preview: true, event: ev.title, mail: mr.ok ? "sent" : mr.error });
    }
    if (dry) { previewHtml = html; results.push({ event: ev.title, start, empfaenger: ev.participants.map((id: string) => empBy[id] && (empBy[id].email_internal || empBy[id].email)).filter(Boolean), abgeschaltet: ev.participants.filter((id: string) => off.has(id)).length }); continue; }
    for (const empId of ev.participants) {
      if (off.has(empId)) { results.push({ event: ev.title, emp: empId, skipped: "abgeschaltet" }); continue; }
      const emp = empBy[empId]; const to = emp && (emp.email_internal || emp.email);
      if (!to) { results.push({ event: ev.title, emp: empId, skipped: "keine Mail" }); continue; }
      // Anspruch zuerst: gelingt der Einfügen-Versuch nicht (Unique), hat ein anderer Lauf schon gesendet
      const { error: claimErr } = await sb.from("calendar_reminders_sent").insert({ event_id: ev.id, occurrence_date: today, employee_id: empId, channel: "mail+slack" });
      if (claimErr) { results.push({ event: ev.title, emp: empId, skipped: "schon gesendet" }); continue; }
      const mr = sender ? await smtpSend(sender, to, subject, html) : { ok: false, error: "kein Absender" };
      const sr = await slackDM(to, slackTxt);
      results.push({ event: ev.title, to, mail: mr.ok ? "sent" : mr.error, slack: sr });
    }
  }
  return json({ ok: true, due: due.length, results, ...(dry ? { html: previewHtml } : {}) });
});
