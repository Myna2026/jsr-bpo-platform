// Sales-Akquise: Versand-Rhythmus (Drip). Läuft minütlich per Cron, sendet aber nur verteilt: zufällig alle 3-7 Min
// eine oder zwei Mails, nur im Zeitfenster (Default Mo-Fr 8-17 Uhr Europe/Berlin), unter Tages-Deckel MIT Aufwärmphase
// (neues Postfach → erst wenig, dann schrittweise hoch, sonst Spam). Kein Massenversand aus einem Postfach.
// Verteilt BEIDE Ströme: fällige Nachfasser + (wenn Autonomie an) Erstkontakte an die höchstpriorisierten Leads.
// Config jsr_sales_pace_v1 (einstellbar), Zustand jsr_sales_pace_state_v1 (next_send_at). Öffentlich (--no-verify-jwt).
// Deploy: supabase functions deploy sales-dispatch --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { deliverStage } from "../_shared/sales_core.ts";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC = Deno.env.get("ANTHROPIC_API_KEY") || "";
const CHAIN_DEFAULT: Record<string, string | null> = { erstansprache: "nachfass1", nachfass1: "nachfass2", nachfass2: "letzter", letzter: null, reaktivierung: null };
function json(b: unknown, s = 200) { return new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } }); }
function rnd(min: number, max: number) { return min + Math.random() * (max - min); }

function berlinNow(tz: string) {
  const now = new Date();
  const p = new Intl.DateTimeFormat("en-GB", { timeZone: tz, weekday: "short", hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false }).formatToParts(now);
  const g = (t: string) => p.find((x) => x.type === t)?.value || "";
  const wd: Record<string, number> = { Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 };
  let hour = Number(g("hour")); if (hour === 24) hour = 0;
  return { now, weekday: wd[g("weekday")] || 0, hour, minute: Number(g("minute")), second: Number(g("second")) };
}
// Effektiver Tages-Deckel mit Aufwärmphase: warmup_days lang flach auf warmup_cap, dann über ramp_days hoch auf daily_cap.
function effectiveCap(pace: any, dailyCap: number) {
  const wc = Number(pace.warmup_cap) || 25, wd = Number(pace.warmup_days) || 14, rd = Number(pace.ramp_days) || 14;
  if (!pace.warmup_start) return dailyCap;
  const day = Math.floor((Date.now() - Date.parse(pace.warmup_start)) / 864e5);
  if (day < 0) return Math.min(wc, dailyCap);
  if (dailyCap <= wc) return dailyCap;
  if (day < wd) return wc;
  if (day < wd + rd) return Math.round(wc + (dailyCap - wc) * (day - wd) / rd);
  return dailyCap;
}

Deno.serve(async (_req) => {
  const sb = createClient(SB_URL, SERVICE);
  const cfg = async (k: string) => (await sb.from("app_config").select("value").eq("key", k).maybeSingle()).data?.value as any || {};
  const pace = await cfg("jsr_sales_pace_v1");
  const auton = await cfg("jsr_sales_autonomy_v1");
  const state = await cfg("jsr_sales_pace_state_v1");
  if (auton.enabled !== true) return json({ ok: true, skipped: "autonomy_off" });

  const tz = pace.timezone || "Europe/Berlin";
  const days: number[] = Array.isArray(pace.days) && pace.days.length ? pace.days : [1, 2, 3, 4, 5];
  const hStart = pace.hour_start != null ? Number(pace.hour_start) : 8;
  const hEnd = pace.hour_end != null ? Number(pace.hour_end) : 17;
  const b = berlinNow(tz);
  if (!days.includes(b.weekday) || b.hour < hStart || b.hour >= hEnd) return json({ ok: true, skipped: "outside_window", weekday: b.weekday, hour: b.hour });

  // Rhythmus-Sperre: erst wieder senden, wenn der zufällige Abstand um ist.
  if (state.next_send_at && b.now < new Date(state.next_send_at)) return json({ ok: true, skipped: "not_yet", next: state.next_send_at });

  // Tages-Deckel (nur erfolgreiche autonome Sends heute, Berlin-Tag).
  const midnight = new Date(b.now.getTime() - (((b.hour * 60 + b.minute) * 60 + b.second) * 1000));
  const { count: sentToday } = await sb.from("sales_events").select("id", { count: "exact", head: true })
    .eq("kind", "sent").is("actor", null).eq("detail->>ok", "true").gte("occurred_at", midnight.toISOString());
  const cap = effectiveCap(pace, Number(auton.daily_cap) || 15);
  let remaining = cap - (sentToday || 0);
  if (remaining <= 0) return json({ ok: true, skipped: "cap_reached", cap, sentToday: sentToday || 0 });

  const chain: Record<string, string | null> = { ...CHAIN_DEFAULT, ...(await cfg("jsr_sales_followup_v1")).chain };
  const pickTpl = async (stage: string) => { const { data } = await sb.from("sales_templates").select("*").eq("stage", stage).eq("active", true); return (data && data.length) ? data[Math.floor(Math.random() * data.length)] : null; };

  // Warteschlange: fällige Nachfasser zuerst (zeitkritisch), dann Erstkontakte nach Priorität (wenn erlaubt).
  const queue: Array<{ lead: any; stage: string }> = [];
  const { data: dueFollow } = await sb.from("sales_leads").select("*").in("status", ["contacted", "opened"]).lte("next_followup_at", b.now.toISOString()).not("contact_email", "is", null).order("next_followup_at", { ascending: true }).limit(30);
  for (const l of dueFollow || []) {
    const ns = chain[l.stage || "erstansprache"];
    if (!ns) { await sb.from("sales_leads").update({ next_followup_at: null }).eq("id", l.id); continue; }  // Kette zu Ende
    queue.push({ lead: l, stage: ns });
  }
  if (auton.auto_first_contact !== false) {
    const { data: fresh } = await sb.from("sales_leads").select("*").eq("status", "researched").not("contact_email", "is", null).order("score", { ascending: false, nullsFirst: false }).limit(30);
    for (const l of fresh || []) queue.push({ lead: l, stage: "erstansprache" });
  }

  // Ein oder zwei je Tick, nie über den Rest-Deckel.
  const batchMin = Number(pace.batch_min) || 1, batchMax = Number(pace.batch_max) || 2;
  const want = Math.min(batchMin + Math.floor(Math.random() * (batchMax - batchMin + 1)), remaining, queue.length);
  let sent = 0; const errors: string[] = [];
  for (let i = 0; i < want; i++) {
    const item = queue[i];
    const tpl = await pickTpl(item.stage);
    if (!tpl) { if (item.stage !== "erstansprache") await sb.from("sales_leads").update({ next_followup_at: new Date(Date.now() + 3 * 864e5).toISOString() }).eq("id", item.lead.id); continue; }
    const r = await deliverStage(sb, item.lead, tpl, null, { anthropic: ANTHROPIC, auto: item.stage === "erstansprache" ? "erstkontakt" : "nachgefasst" });
    if (r.ok) { sent++; remaining--; } else if (r.error) errors.push((item.lead.company || "?") + ": " + r.error);
    if (remaining <= 0) break;
  }

  // Nächsten Versandzeitpunkt zufällig setzen (nur wenn wirklich gesendet wurde).
  if (sent > 0) {
    const gapMin = Number(pace.gap_min_minutes) || 3, gapMax = Number(pace.gap_max_minutes) || 7;
    const next = new Date(Date.now() + rnd(gapMin, gapMax) * 60000).toISOString();
    await sb.from("app_config").upsert({ key: "jsr_sales_pace_state_v1", value: { next_send_at: next, last_sent_at: new Date().toISOString() } }, { onConflict: "key" });
  }
  return json({ ok: true, sent, cap, sentToday: (sentToday || 0) + sent, queued: queue.length, errors: errors.slice(0, 5) });
});
