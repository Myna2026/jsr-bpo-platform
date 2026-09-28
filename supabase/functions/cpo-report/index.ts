// Annas CPO-Report, zweimal am Tag: 13:00 der Zwischenstand, 19:15 der Tagesabschluss
// (nach dem Ende der Spätschicht um 19:00, damit die letzten Vorgänge drin sind).
// Inhalt: CPO-Umsatz bis zu diesem Zeitpunkt, Stundenumsatz, Summe — dazu die drei besten und die
// zwei schwächsten Agenten des Tages. Empfänger: info@mynaai.de, Thorsten, Rajner.
//
// Gerechnet wird exakt wie im Retention Overview:
//  - CPO-Umsatz = Summe der beim Erfassen eingefrorenen CPOs (cpo_entries.cpo_amount), ohne Stornos.
//  - Stundenumsatz = produktive Nettostunden aus shift_assignments, abzüglich Urlaub/Krankheit,
//    und NUR für Agenten, die an diesem Tag auch Vorgänge erfasst haben. Satz und Schalter stehen in
//    app_config.jsr_retention_hourly_v1; ohne Schicht im Plan greift der dort hinterlegte Rückfallwert.
//  - Um 13:00 zählen nur die bis dahin gelaufenen Stunden (anteilig an der Schicht), abends der
//    volle geplante Tag. Vorgänge zählen bis zum Absendezeitpunkt.
//
// Cron ruft alle 5 Minuten ohne Körper auf; die Function feuert nur in ihrem Zeitfenster und
// schreibt den Anspruch vorher nach cpo_report_log (Primärschlüssel Tag+Fenster) — so geht nichts doppelt raus.
// Aufrufe: {mode:"send", slot:"13"|"19"} erzwingt einen Lauf · {mode:"test", to:"..."} eine Testmail
// an genau eine Adresse · {dry:true} rechnet nur und gibt die Zahlen zurück.
// Deploy: supabase functions deploy cpo-report --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { agentBrand, shell, lead, tiles, perfRow, callout, button, refLine, PORTAL_URL } from "../_shared/agent_mail.ts";
import { smtpSend, agentMailSender } from "../_shared/agent_send.ts";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

const PROJ = "proj_gn_e5f6a7b8", SKILL = "retention";
const OWNER_MAIL = "info@mynaai.de";
const FALLBACK_TO = ["consulting@25hrs.net", "r.gore@tiramu.de"];   // Thorsten, Rajner
const HOURLY_KEY = "jsr_retention_hourly_v1";

const AGENT_POS = ["Agent", "Senior Agent", "ASP", "Supervisor"];   // Kategorie "agent" laut docs/fachmodell
function istAgent(emp: any) { return !!emp && AGENT_POS.indexOf(String(emp.position || "").trim()) >= 0; }
function berlinNow() { return new Date(new Date().toLocaleString("en-US", { timeZone: "Europe/Berlin" })); }
function iso(d: Date) { return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); }
function eur(v: number) { return (Math.round((v || 0) * 100) / 100).toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + " €"; }
function hrs(v: number) { return (Math.round((v || 0) * 10) / 10).toLocaleString("de-DE", { minimumFractionDigits: 1, maximumFractionDigits: 1 }) + " h"; }
function dmy(ds: string) { const [y, m, d] = ds.split("-"); return Number(d) + "." + Number(m) + "." + y; }

// Brutto-Spannen einer Schichtzelle ("09:00-17:30", Split mit "|")
function spans(v: string) {
  const out: { s: number; e: number }[] = [];
  String(v || "").split("|").forEach((p) => {
    const m = String(p).trim().match(/^(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})$/); if (!m) return;
    const a = Number(m[1].slice(0, 2)) * 60 + Number(m[1].slice(3));
    let b = Number(m[2].slice(0, 2)) * 60 + Number(m[2].slice(3));
    if (b <= a) b += 1440;
    out.push({ s: a, e: b });
  });
  return out;
}
// Abwesenheit kürzt: ganztags auf null, halber Tag auf die Hälfte.
function absFactor(emp: any, ds: string) {
  const list = (emp && emp.absences) || [];
  for (const a of list) {
    const f = String(a.from || "").slice(0, 10); if (!f) continue;
    const t = String(a.to || f).slice(0, 10);
    if (ds >= f && ds <= t) {
      const d = Number(a.days);
      if (t === f && isFinite(d) && d > 0 && d < 1) return Math.max(0, 1 - d);
      return 0;
    }
  }
  return 1;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* Cron ohne Körper */ }

  const now = berlinNow();
  const mins = now.getHours() * 60 + now.getMinutes();
  const isTest = body.mode === "test" || !!body.to;
  const dry = body.dry === true;
  const forced = typeof body.slot === "string";
  const forcedRun = forced || isTest || dry;
  // Zeitfenster in Berliner Zeit: 13:00 und 19:15, je fünf Minuten breit (Cron alle 5 Minuten).
  const fenster = (mins >= 780 && mins < 785) ? "13" : (mins >= 1155 && mins < 1160) ? "19" : null;
  const slot: string = forced ? String(body.slot) : (fenster || "");
  if (!slot) return json({ ok: true, skipped: "kein Zeitfenster", berlin: now.toISOString() });
  const cut = slot === "13" ? 13 * 60 : 19 * 60 + 15;               // Minuten seit Mitternacht
  const today = String(body.day || iso(now));

  // Anspruch VOR dem Senden schreiben; ein zweiter Lauf im selben Fenster laeuft am Schluessel auf.
  if (!isTest && !dry) {
    const { error: claimErr } = await sb.from("cpo_report_log").insert({ day: today, slot });
    if (claimErr) return json({ ok: true, skipped: "schon versendet", day: today, slot });
  }

  // Sa/So nur, wenn tatsaechlich erfasst wurde — sonst bleibt der Posteingang still.
  const wochenende = now.getDay() === 0 || now.getDay() === 6;
  if (wochenende && !forcedRun) {
    const { count } = await sb.from("cpo_entries").select("id", { count: "exact", head: true })
      .eq("project_id", PROJ).eq("skill", SKILL).eq("work_date", today).is("cancelled_at", null);
    if (!count) return json({ ok: true, skipped: "Wochenende ohne Erfassung" });
  }

  // ── Daten ─────────────────────────────────────────────────────────────────
  const [{ data: ents }, { data: shifts }, { data: cfgRow }] = await Promise.all([
    sb.from("cpo_entries").select("employee_id,work_date,case_no,is_close,cpo_amount,created_at,cancelled_at")
      .eq("project_id", PROJ).eq("skill", SKILL).eq("work_date", today),
    sb.from("shift_assignments").select("employee_id,shift_value,net_hours").eq("project_id", PROJ).eq("skill", SKILL).eq("work_date", today),
    sb.from("app_config").select("value").eq("key", HOURLY_KEY).maybeSingle(),
  ]);
  const hcfgAll = (cfgRow && (cfgRow as any).value) || {};
  const hc = hcfgAll[PROJ + "/" + SKILL] || {};
  const HRL = { on: !!hc.on, rate: Number(hc.rate) || 12.5, fallback: Number(hc.fallback) || 7.5 };

  // Vorgänge bis zum Stichzeitpunkt, ohne Stornos
  const live = (ents || []).filter((r: any) => {
    if (r.cancelled_at) return false;
    const t = new Date(new Date(r.created_at).toLocaleString("en-US", { timeZone: "Europe/Berlin" }));
    return (t.getHours() * 60 + t.getMinutes()) <= cut;
  });
  const ids = [...new Set(live.map((r: any) => r.employee_id))];
  const shiftIds = [...new Set((shifts || []).map((s: any) => s.employee_id))];
  const allIds = [...new Set([...ids, ...shiftIds])];
  const { data: emps } = allIds.length
    ? await sb.from("employees").select("id,first_name,last_name,position,absences").in("id", allIds)
    : { data: [] as any[] };
  const empBy: Record<string, any> = {}; (emps || []).forEach((e: any) => { empBy[e.id] = e; });
  const shiftBy: Record<string, any> = {}; (shifts || []).forEach((s: any) => { shiftBy[s.employee_id] = s; });

  // ── Je Agent rechnen ──────────────────────────────────────────────────────
  const rows = ids.map((id) => {
    const mine = live.filter((r: any) => r.employee_id === id);
    const cls = mine.filter((r: any) => r.is_close);
    const rev = cls.reduce((a: number, r: any) => a + (Number(r.cpo_amount) || 0), 0);
    const emp = empBy[id] || {};
    const f = absFactor(emp, today);
    const sh = shiftBy[id];
    const agent = istAgent(emp);          // Overhead bekommt keine Stundenvergütung
    let paid = 0, fb = false;
    if (!agent) { /* keine Stunden */ }
    else if (sh) {
      const sp = spans(sh.shift_value);
      const gross = sp.reduce((a, x) => a + (x.e - x.s), 0);
      const done = sp.reduce((a, x) => a + Math.max(0, Math.min(cut, x.e) - x.s), 0);
      const net = Number(sh.net_hours) || (gross ? Math.max(0, gross / 60 - 1) : 0);
      paid = net * f * (slot === "13" ? (gross ? Math.min(1, done / gross) : 0) : 1);
    } else {
      fb = true;
      paid = HRL.fallback * (slot === "13" ? Math.max(0, Math.min(1, (cut - 540) / 510)) : 1);
    }
    const name = ((emp.first_name || "") + " " + (emp.last_name || "")).trim() || "Unbekannt";
    return { id, name, agent, n: mine.length, cl: cls.length, rev, paid: HRL.on ? paid : 0, fb,
             hourRev: HRL.on ? paid * HRL.rate : 0, quote: mine.length ? cls.length / mine.length : 0 };
  }).sort((a, b) => b.rev - a.rev || b.cl - a.cl);

  const sum = (k: string) => rows.reduce((a: number, r: any) => a + (Number(r[k]) || 0), 0);
  const total = { n: sum("n"), cl: sum("cl"), rev: sum("rev"), paid: sum("paid"), hourRev: sum("hourRev") };
  const gesamt = total.rev + total.hourRev;
  const quote = total.n ? Math.round(total.cl / total.n * 100) : 0;
  const fbCount = rows.filter((r) => r.fb && r.agent).length;
  const planLos = shiftIds.length === 0;

  const best = rows.slice(0, 3);
  const schwach = rows.length > 3 ? rows.slice(-2).filter((r) => !best.some((b) => b.id === r.id)) : [];

  if (dry) return json({ ok: true, slot, today, total, gesamt, quote, rows, hourly: HRL, fbCount });

  // ── Mail bauen ────────────────────────────────────────────────────────────
  const brandKey = ((await agentMailSender(sb, "anna")) ? "anna" : "max");
  const brand = await agentBrand(sb, brandKey);
  const titel = slot === "13" ? "Retention, Zwischenstand 13:00" : "Retention, Tagesabschluss";
  const unter = dmy(today) + " · Deutsche GigaNetz, Retention" + (slot === "13" ? " · Stand 13:00 Uhr" : " · nach Ende der Spätschicht");

  // Drei Kacheln statt vier: bei vier Spalten ist ein vierstelliger Betrag zu breit. Vorgänge und
  // Quote stehen dafür im Vorspann, wo sie ohnehin besser lesbar sind.
  const kacheln = HRL.on
    ? tiles([
        { big: eur(gesamt), label: "Gesamtumsatz", sub: total.n + " Vorgänge · " + quote + " % Quote" },
        { big: eur(total.rev), label: "CPO-Umsatz", sub: total.cl + (total.cl === 1 ? " Abschluss" : " Abschlüsse") },
        { big: eur(total.hourRev), label: "Stundenumsatz", sub: hrs(total.paid) + " × " + eur(HRL.rate) },
      ])
    : tiles([
        { big: eur(total.rev), label: "CPO-Umsatz", sub: total.cl + (total.cl === 1 ? " Abschluss" : " Abschlüsse") },
        { big: String(total.n), label: "Vorgänge", sub: quote + " % Abschlussquote" },
        { big: String(rows.length), label: "Agenten am Tag", sub: "mit erfassten Vorgängen" },
      ]);

  const maxRev = Math.max(1, ...rows.map((r) => r.rev));
  const zeile = (r: any, tone: string, badge?: string) => perfRow({
    name: r.name, value: eur(r.rev), tone, badge,
    note: r.cl + " Abschlüsse aus " + r.n + " Vorgängen · " + Math.round(r.quote * 100) + " % Quote"
          + (HRL.on ? " · " + eur(r.hourRev) + " Stunden" : ""),
    valuePct: Math.round(r.rev / maxRev * 100),
  });

  let inner = lead("<b>" + eur(gesamt) + "</b> " + (slot === "13" ? "stehen bis 13:00 Uhr auf der Uhr" : "sind heute zusammengekommen") + ". "
    + (HRL.on ? ("Davon " + eur(total.rev) + " aus Abschlüssen und " + eur(total.hourRev) + " aus " + hrs(total.paid) + " produktiver Zeit.")
              : (total.cl + " Abschlüsse aus " + total.n + " Vorgängen.")));
  inner += kacheln;

  if (best.length) {
    inner += '<tr><td style="padding:16px 16px 4px;font-size:13px;font-weight:bold;color:#0f2830;">Die drei Besten</td></tr>';
    best.forEach((r, i) => { inner += zeile(r, "good", ["🥇", "🥈", "🥉"][i]); });
  }
  if (schwach.length) {
    inner += '<tr><td style="padding:16px 16px 4px;font-size:13px;font-weight:bold;color:#0f2830;">Die zwei schwächsten</td></tr>';
    schwach.forEach((r) => { inner += zeile(r, "warn"); });
  }
  if (!rows.length) {
    inner += callout("Noch nichts erfasst", "Bis " + (slot === "13" ? "13:00" : "19:15") + " Uhr ist für heute kein Vorgang eingetragen.", "#d97706");
  }
  if (planLos && rows.length) {
    inner += callout("Kein Schichtplan für heute",
      "Für diesen Tag steht keine Schicht im Plan. Die Stunden sind deshalb mit dem Rückfallwert von "
      + hrs(HRL.fallback) + " je Agent gerechnet.", "#d97706");
  } else if (fbCount) {
    inner += callout("Schichtplan unvollständig",
      fbCount + (fbCount === 1 ? " Agent hat" : " Agenten haben") + " heute erfasst, ohne im Plan zu stehen. Für "
      + (fbCount === 1 ? "ihn" : "sie") + " rechnet der Report mit " + hrs(HRL.fallback) + ". Sobald der Plan gepflegt ist, greift er automatisch.", "#d97706");
  }
  inner += button(PORTAL_URL + "?goto=cpotrack", "Retention Overview öffnen", brand.accent);
  inner += refLine(slot === "13"
    ? "Zwischenstand: Vorgänge bis 13:00 Uhr, Stunden anteilig bis 13:00 Uhr."
    : "Tagesabschluss um 19:15 Uhr, nach dem Ende der Spätschicht: alle Vorgänge des Tages, Stunden für den geplanten Tag.");

  const html = shell(brand, titel, unter, inner);
  const subject = (isTest ? "[Test] " : "") + titel + " · " + eur(gesamt);
  if (body.html === true) return new Response(html, { headers: { ...cors, "Content-Type": "text/html; charset=utf-8" } });

  // ── Empfänger ─────────────────────────────────────────────────────────────
  let to: string[] = [];
  if (isTest) {
    to = [String(body.to || OWNER_MAIL)];
  } else {
    const { data: us } = await sb.from("app_users").select("user_id,full_name").or("full_name.ilike.%Thorsten%,full_name.ilike.%Rajner%");
    const uids = (us || []).map((u: any) => u.user_id);
    const mails: string[] = [];
    for (const uid of uids) {
      const { data: au } = await sb.auth.admin.getUserById(uid);
      const m = au?.user?.email; if (m) mails.push(m);
    }
    to = [...new Set([OWNER_MAIL, ...(mails.length ? mails : FALLBACK_TO)])];
  }

  // Absender: Anna, sobald sie ein Postfach hat. Solange nicht, übernimmt Max — sein Feld ist genau
  // das Melden, wenn etwas auffällt, und er hat eine Adresse. Kein Code-Wechsel nötig, wenn Anna
  // ihr Postfach bekommt: dann greift sie automatisch.
  const sender = (await agentMailSender(sb, "anna")) || (await agentMailSender(sb, "max"));
  if (!sender) return json({ ok: false, error: "Kein Absender mit Postfach gefunden" }, 500);
  const results: any[] = [];
  for (const adr of to) {
    const r = await smtpSend(sender, adr, subject, html);
    results.push({ to: adr, ok: r.ok, error: r.error });
  }
  return json({ ok: results.every((r) => r.ok), slot, today, to, gesamt, cpo: total.rev, stunden: total.hourRev, agenten: rows.length, results });
});
