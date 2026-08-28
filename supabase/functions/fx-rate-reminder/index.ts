// Max erinnert rechtzeitig vor dem Lohnlauf am 10. an den Wechselkurs — damit er eingetragen ist, wenn
// gerechnet wird. An Shkurte, Rajner und info@mynaai.de. Nur wenn der Kurs des zu zahlenden Monats FEHLT.
// jsr_fx_rates_v1 = { "YYYY-MM": kurs }. Der Lohnlauf am 10. zahlt den Vormonat -> Zielmonat = Vormonat.
// Cron: Tage 3–9, Mo–Fr; 2-Tage-Sperre gegen tägliches Nörgeln. Kanäle Mail (max@) + Slack.
// Deploy: supabase functions deploy fx-rate-reminder --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { agentBrand, shell, lead, tiles, metricCard, callout, button, linkGoto } from "../_shared/agent_mail.ts";
import { smtpSend, slackDM, agentMailSender } from "../_shared/agent_send.ts";
import { scheduleDue, getSchedule } from "../_shared/schedule.ts";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const CADENCE_MS = 2 * 864e5;
// Empfänger: Rajner + Shkurte (per uid) und „mich".
const RECIP_UIDS = ["14a5001c-9efb-4f76-b8f8-145e24b4be5f", "54f067ab-b6f8-47a1-afa7-6dcb86b89b29"];
const OWNER_MAIL = "info@mynaai.de";
const MON = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"];

function berlinNow() { return new Date(new Date().toLocaleString("en-US", { timeZone: "Europe/Berlin" })); }

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* Cron */ }
  const previewTo = (typeof body.preview_to === "string" && body.preview_to.includes("@")) ? body.preview_to : null;
  const force = body.force === true || !!previewTo, dry = body.dry === true;
  const sched = await getSchedule(sb, "fx_rate");
  if (!force && !scheduleDue(sched)) return json({ ok: true, skipped: "not-scheduled" });

  // Zielmonat = Vormonat (der Lohnlauf am 10. zahlt den abgelaufenen Monat)
  const n = berlinNow();
  const prev = new Date(Date.UTC(n.getFullYear(), n.getMonth() - 1, 1));
  const key = prev.getUTCFullYear() + "-" + String(prev.getUTCMonth() + 1).padStart(2, "0");
  const monLabel = MON[prev.getUTCMonth()] + " " + prev.getUTCFullYear();

  const { data: cfg } = await sb.from("app_config").select("value").eq("key", "jsr_fx_rates_v1").maybeSingle();
  const rates = (cfg && cfg.value) || {};
  const rate = rates[key];
  if (!previewTo && rate != null && rate !== "" && Number(rate) > 0) return json({ ok: true, state: "set", month: key, rate });

  // Kadenz: nur alle 2 Tage
  if (!force) { const { data: last } = await sb.from("agent_actions").select("at").eq("agent_key", "max").eq("kind", "fx_rate_reminder").order("at", { ascending: false }).limit(1);
    if (last && last[0] && (Date.now() - new Date(last[0].at).getTime()) < CADENCE_MS) return json({ ok: true, skipped: "cadence", month: key }); }

  const brand = await agentBrand(sb, "max", "#2563eb");
  // Letzte zwei Monatskurse zur Größenordnung + Zielmonat deutlich als fehlend.
  const mkey = (d: Date) => d.getUTCFullYear() + "-" + String(d.getUTCMonth() + 1).padStart(2, "0");
  const mlab = (d: Date) => MON[d.getUTCMonth()] + " " + d.getUTCFullYear();
  const p1 = new Date(Date.UTC(prev.getUTCFullYear(), prev.getUTCMonth() - 1, 1));
  const p2 = new Date(Date.UTC(prev.getUTCFullYear(), prev.getUTCMonth() - 2, 1));
  const fmtRate = (r: any) => (r != null && r !== "" && Number(r) > 0) ? Number(r).toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) : null;
  const r1 = fmtRate(rates[mkey(p1)]), r2 = fmtRate(rates[mkey(p2)]);
  const leadTxt = "Der Wechselkurs für den Lohnlauf am 10. fehlt noch. So lagen die letzten Monate, und das ist die Lücke:";
  const knownTiles = tiles([
    { big: r2 || "—", label: mlab(p2), sub: r2 ? "ALL / 1 €" : "kein Wert" },
    { big: r1 || "—", label: mlab(p1), sub: r1 ? "ALL / 1 €" : "kein Wert" },
  ]);
  const missing = metricCard({ name: mlab(prev) + " (Zielmonat)", value: "fehlt", tone: "bad", note: "Diesen Kurs braucht der Lohnlauf am 10." });
  const folge = callout("Ohne Kurs kein Lohnlauf", "Ist der Kurs am 10. nicht eingetragen, rechnet der Lauf mit einem veralteten oder gar keinem Kurs, und die LEK-Gehälter stimmen nicht. Zwei Minuten jetzt sparen die Korrektur hinterher.", brand.accent);
  const html = shell(brand, "Wechselkurs fehlt für den Lohnlauf", "Zielmonat " + monLabel, lead(leadTxt) + knownTiles + missing + folge + button(linkGoto("fx"), "Kurs jetzt eintragen", brand.accent));
  const slackText = "*Max · Wechselkurs*\nDer Kurs für " + monLabel + " fehlt noch. Der Lohnlauf am 10. braucht ihn — bitte vorher eintragen.";

  // Empfänger auflösen (bei Vorschau nur an dich)
  let emails: string[] = previewTo ? [previewTo] : [OWNER_MAIL];
  if (!previewTo) try { const { data: al } = await sb.auth.admin.listUsers({ perPage: 200 }); const byId: Record<string, string> = {}; (al?.users || []).forEach((u: any) => { if (u.email) byId[u.id] = u.email; });
    RECIP_UIDS.forEach((uid) => { if (byId[uid]) emails.push(byId[uid]); }); } catch (_e) {}
  emails = [...new Set(emails)];
  if (dry) return json({ ok: true, dry: true, month: key, emails, html });

  const sender = await agentMailSender(sb, "max");
  const results: any[] = [];
  for (const to of emails) { const mr = sender ? await smtpSend(sender, to, (previewTo ? "[Vorschau] " : "") + "Wechselkurs für den Lohnlauf (" + monLabel + ")", html) : { ok: false, error: "kein Absender" };
    const sr = previewTo ? "skip-preview" : await slackDM(to, slackText); results.push({ to, mail: mr.ok ? "sent" : mr.error, slack: sr }); }
  if (!previewTo) { try { await sb.from("agent_actions").insert({ agent_key: "max", kind: "fx_rate_reminder", meta: { month: key, recipients: emails.length } }); } catch (_e) {} }
  return json({ ok: true, preview: !!previewTo, state: "reminded", month: key, results });
});
