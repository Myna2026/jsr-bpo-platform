// Max erinnert Edi alle zwei Werktage an offene Uploads — solange sie nicht vollständig sind.
//  nichts hochgeladen  -> Hinweis auf ALLES Offene
//  teilweise           -> Hinweis auf das, was NOCH fehlt
//  vollständig         -> KEINE Nachricht
// Kein Wochenende. Kanäle: Mail (max@25hrs.net) UND Slack. Kadenz „alle 2 Tage" via Abstand zur letzten Meldung.
// Cron: Mo–Fr morgens; die 2-Tage-Sperre drosselt auf jeden zweiten Werktag.
// Vollständigkeit = deckt report_forecast die kommenden Wochen ab (der Forecast-Upload schreibt dorthin).
// Deploy: supabase functions deploy edi-upload-reminder --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { agentBrand, shell, lead, block, button, PORTAL_URL } from "../_shared/agent_mail.ts";
import { smtpSend, slackDM, agentMailSender } from "../_shared/agent_send.ts";
import { isWeekendBerlin } from "../_shared/schedule.ts";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const EDI_UID = "f8c5fe64-7319-455b-8c3b-ddfc59e7e7fe";
const CADENCE_MS = 2 * 864e5;   // alle 2 Tage

function isoOf(d: Date) { const x = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate())); const day = (x.getUTCDay() + 6) % 7; x.setUTCDate(x.getUTCDate() - day + 3); const firstTh = new Date(Date.UTC(x.getUTCFullYear(), 0, 4)); const week = 1 + Math.round(((x.getTime() - firstTh.getTime()) / 86400000 - 3 + ((firstTh.getUTCDay() + 6) % 7)) / 7); return { year: x.getUTCFullYear(), kw: week }; }
function skillLabel(s: string) { return s === "sales" ? "Sales" : s === "support" ? "Support" : s; }

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* leerer Body ok (Cron) */ }
  const previewTo = (typeof body.preview_to === "string" && body.preview_to.includes("@")) ? body.preview_to : null;
  const force = body.force === true || !!previewTo;
  const dry = body.dry === true;
  if (isWeekendBerlin() && !force) return json({ ok: true, skipped: "weekend" });

  // Edis aktive Upload-Quellen
  const { data: srcs } = await sb.from("upload_schedule").select("project_id,source_type").eq("active", true).eq("responsible_user", EDI_UID);
  if (!srcs || !srcs.length) return json({ ok: true, note: "keine Quellen für Edi" });

  // Kommende zwei Wochen, die der Forecast abdecken muss
  const now = new Date();
  // demo/preview (nie im Cron): erzwingt den Offen-Zustand zum Prüfen der Nachricht.
  const weeks = (body.demo || previewTo) ? [{ year: 2099, kw: 1 }, { year: 2099, kw: 2 }] : [isoOf(new Date(now.getTime() + 7 * 864e5)), isoOf(new Date(now.getTime() + 14 * 864e5))];
  const projName: Record<string, string> = {};
  for (const s of srcs) { if (!projName[s.project_id]) { const { data } = await sb.from("projects").select("name").eq("id", s.project_id).maybeSingle(); projName[s.project_id] = (data && data.name) || "?"; } }

  const open: { label: string }[] = [];
  for (const s of srcs) {
    let complete = false;
    if (String(s.source_type).startsWith("forecast_")) {
      const skill = String(s.source_type).replace("forecast_", "");
      const orC = weeks.map((w) => `and(year.eq.${w.year},kw.eq.${w.kw})`).join(",");
      const { data: fc } = await sb.from("report_forecast").select("year,kw").eq("project_id", s.project_id).eq("skill", skill).gt("fc_hours", 0).or(orC);
      const covered = new Set((fc || []).map((r: any) => r.year + "-" + r.kw));
      complete = weeks.every((w) => covered.has(w.year + "-" + w.kw));
      if (!complete) open.push({ label: "Forecast " + skillLabel(skill) + " (" + projName[s.project_id] + ")" });
    } else {
      // Fallback für andere Quellen: im aktuellen Monat ein data_imports-Eintrag vorhanden?
      const mStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString();
      const { count } = await sb.from("data_imports").select("*", { count: "exact", head: true }).eq("project_id", s.project_id).eq("source_type", s.source_type).gte("created_at", mStart);
      complete = (count || 0) > 0;
      if (!complete) open.push({ label: s.source_type + " (" + projName[s.project_id] + ")" });
    }
  }

  if (!open.length) { try { await sb.from("agent_actions").insert({ agent_key: "max", kind: "edi_upload_complete", meta: {} }); } catch (_e) {} return json({ ok: true, state: "complete" }); }

  // Kadenz: nur alle 2 Tage, nicht täglich nörgeln
  if (!force) { const { data: last } = await sb.from("agent_actions").select("at").eq("agent_key", "max").eq("kind", "edi_upload_reminder").order("at", { ascending: false }).limit(1);
    if (last && last[0] && (Date.now() - new Date(last[0].at).getTime()) < CADENCE_MS) return json({ ok: true, skipped: "cadence", open: open.map((o) => o.label) }); }

  // Nachricht in Max' Stimme, je nach Zustand
  const allOpen = open.length === srcs.length;
  const list = open.map((o) => o.label);
  const leadTxt = allOpen
    ? "Deine Upload-Aufgaben stehen noch komplett aus. Ohne den Forecast bleibt der Soll-Ist-Vergleich für die kommenden Wochen leer:"
    : "Fast vollständig. Es fehlt noch, dann ist es komplett:";
  const listHtml = '<ul style="margin:6px 0 0;padding-left:20px;font-size:14px;line-height:1.7;color:#1f2937">' + list.map((l) => "<li>" + l.replace(/</g, "&lt;") + "</li>").join("") + "</ul>";

  const brand = await agentBrand(sb, "max", "#2563eb");
  const inner = lead(leadTxt) + block(listHtml) + button(PORTAL_URL, "Zum Datenimport →", brand.accent);
  const html = shell(brand, allOpen ? "Uploads stehen aus" : "Uploads fast vollständig", "Forecast Holidaycheck", inner);
  const slackText = "*Max · Uploads*\n" + leadTxt + "\n• " + list.join("\n• ");

  const sender = await agentMailSender(sb, "max");
  const email = previewTo || "edi.shaqiri@25hrs.net";
  if (dry) return json({ ok: true, dry: true, state: allOpen ? "nothing" : "partial", open: list, html });

  const mr = sender ? await smtpSend(sender, email, (previewTo ? "[Vorschau] " : "") + "Deine offenen Uploads", html) : { ok: false, error: "kein Absender" };
  const sr = previewTo ? "skip-preview" : await slackDM(email, slackText);
  if (!previewTo) { try { await sb.from("agent_actions").insert({ agent_key: "max", kind: "edi_upload_reminder", meta: { open: list, mail: mr.ok, slack: sr } }); } catch (_e) {} }
  return json({ ok: true, preview: !!previewTo, state: allOpen ? "nothing" : "partial", open: list, mail: mr.ok ? "sent" : mr.error, slack: sr });
});
