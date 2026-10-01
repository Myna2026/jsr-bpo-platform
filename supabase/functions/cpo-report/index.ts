// Pauls CPO-Report, zweimal am Tag: 13:00 der Zwischenstand, 19:15 der Tagesabschluss
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
// Empfaenger der beiden Tagesreports. Gesucht wird ueber den Namen im Zugang, damit eine geaenderte
// Adresse automatisch mitgeht; die Ersatzadresse greift nur, wenn der Zugang nicht gefunden wird.
// Ylli und Shkurte kommen ab dem 29.09.2026 dazu (Vorgabe vom 28.09.: "ab morgen") — deshalb ein
// Datum und kein sofortiger Wechsel, damit der heutige Abschluss noch an die bisherige Runde geht.
const EXTRA_AB = "2026-09-29";
async function empfaengerFuer(sb: any, today: string): Promise<string[]> {
  const faellig = EMPFAENGER.filter((e) => !e.ab || today >= e.ab);
  const { data: us } = await sb.from("app_users").select("user_id,full_name")
    .or(faellig.map((e) => "full_name.ilike.%" + e.name + "%").join(","));
  const mails: string[] = [];
  for (const e of faellig) {
    const u = (us || []).find((x: any) => String(x.full_name || "").toLowerCase().includes(e.name.toLowerCase()));
    let adr = "";
    if (u) { const { data: au } = await sb.auth.admin.getUserById((u as any).user_id); adr = au?.user?.email || ""; }
    mails.push(adr || e.ersatz);
  }
  return [...new Set([OWNER_MAIL, ...mails])];
}
const EMPFAENGER: { name: string; ersatz: string; ab?: string }[] = [
  { name: "Thorsten", ersatz: "consulting@25hrs.net" },
  { name: "Rajner",   ersatz: "r.gore@tiramu.de" },
  { name: "Ylli",     ersatz: "y.bogiqi@25hrs.net",  ab: EXTRA_AB },
  { name: "Shkurte",  ersatz: "sh.cikaqi@25hrs.net", ab: EXTRA_AB },
];
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
  // Nachversand von Hand: schickt eine schon einmal versendete Mail erneut an die REGULAERE Runde.
  // Schreibt bewusst keinen Anspruch, damit er wiederholbar bleibt; der Cron setzt das Kennzeichen nie.
  const resend = body.resend === true;
  const forcedRun = forced || isTest || dry;
  // Zeitfenster in Berliner Zeit: 13:00 und 19:15, je fünf Minuten breit (Cron alle 5 Minuten).
  const fenster = (mins >= 780 && mins < 785) ? "13" : (mins >= 1155 && mins < 1160) ? "19" : null;
  const slot: string = forced ? String(body.slot) : (fenster || "");
  if (!slot) return json({ ok: true, skipped: "kein Zeitfenster", berlin: now.toISOString() });
  const cut = slot === "13" ? 13 * 60 : 19 * 60 + 15;               // Minuten seit Mitternacht
  const today = String(body.day || iso(now));

  // Anspruch VOR dem Senden schreiben; ein zweiter Lauf im selben Fenster laeuft am Schluessel auf.
  if (!isTest && !dry && !resend) {
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
  const [{ data: ents }, { data: shifts }, { data: cfgRow }, { data: optRow }] = await Promise.all([
    sb.from("cpo_entries").select("employee_id,work_date,case_no,is_close,cpo_amount,created_at,cancelled_at,case_kind")
      .eq("project_id", PROJ).eq("skill", SKILL).eq("work_date", today),
    sb.from("shift_assignments").select("employee_id,shift_value,net_hours").eq("project_id", PROJ).eq("skill", SKILL).eq("work_date", today),
    sb.from("app_config").select("value").eq("key", HOURLY_KEY).maybeSingle(),
    sb.from("app_config").select("value").eq("key", "jsr_cpo_options_v1").maybeSingle(),
  ]);
  // Fallarten: dieselbe Liste, die der Agent im Link sieht. Die Beschriftung kommt aus der Konfiguration,
  // damit eine neue Art ohne Aenderung an dieser Datei in der Mail auftaucht.
  const kindDefs: any[] = (((optRow && (optRow as any).value) || {}).case_kinds) || [];
  const kindLabel = (k: string) => { if (k === "__na") return "ohne Angabe";
    const d = kindDefs.filter((x: any) => x && x.key === k)[0]; return d ? String(d.label || d.key) : k; };
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
    return { id, name, agent, n: mine.length, cl: cls.length, rev, paid: HRL.on ? paid : 0, fb, mine,
             hourRev: HRL.on ? paid * HRL.rate : 0, quote: mine.length ? cls.length / mine.length : 0 };
  }).sort((a, b) => b.rev - a.rev || b.cl - a.cl);

  // Verteilung der Fallarten: Anteil am Tagesgesamt, gezaehlt werden alle Vorgaenge, nicht nur Abschluesse.
  // Vorgaenge ohne Art stammen aus der Zeit vor dem Auswahlschritt und stehen als "ohne Angabe".
  const kindCount: Record<string, number> = {};
  live.forEach((r: any) => { const k = r.case_kind || "__na"; kindCount[k] = (kindCount[k] || 0) + 1; });
  const kindOrder: string[] = [];
  kindDefs.slice().sort((a: any, b: any) => (Number(a.rank) || 99) - (Number(b.rank) || 99))
    .forEach((d: any) => { if (d && d.key && kindOrder.indexOf(d.key) < 0 && (d.active !== false || kindCount[d.key])) kindOrder.push(d.key); });
  Object.keys(kindCount).forEach((k) => { if (k !== "__na" && kindOrder.indexOf(k) < 0) kindOrder.push(k); });
  if (kindCount.__na) kindOrder.push("__na");
  const kindMix = (mine: any[]) => {
    if (!mine.length) return "";
    const c: Record<string, number> = {};
    mine.forEach((r: any) => { const k = r.case_kind || "__na"; c[k] = (c[k] || 0) + 1; });
    return kindOrder.filter((k) => c[k]).map((k) => kindLabel(k) + " " + Math.round(c[k] / mine.length * 100) + " %").join(", ");
  };

  const sum = (k: string) => rows.reduce((a: number, r: any) => a + (Number(r[k]) || 0), 0);
  const total = { n: sum("n"), cl: sum("cl"), rev: sum("rev"), paid: sum("paid"), hourRev: sum("hourRev") };
  const gesamt = total.rev + total.hourRev;
  const quote = total.n ? Math.round(total.cl / total.n * 100) : 0;
  const fbCount = rows.filter((r) => r.fb && r.agent).length;
  const planLos = shiftIds.length === 0;

  // Eine Liste statt Bestenliste und Schlusslicht (Vorgabe 2026-09-28): alle, die telefonieren,
  // nach Umsatz sortiert. Overhead bleibt draussen — wer keine Cases bearbeitet, gehoert nicht in
  // die Leistungsreihe, auch wenn einmal ein Vorgang von ihm kommt.
  const liste = rows.filter((r) => r.agent);
  const schnitt = liste.length ? liste.reduce((a: number, r: any) => a + r.rev, 0) / liste.length : 0;

  const sendeTag = iso(now);
  if (dry) return json({ ok: true, slot, today, sendeTag, empfaenger: await empfaengerFuer(sb, sendeTag), total, gesamt, quote,
                         jeStd: total.paid > 0 ? Math.round((HRL.on ? gesamt : total.rev) / total.paid * 100) / 100 : null,
                         jeStdCpo: total.paid > 0 ? Math.round(total.rev / total.paid * 100) / 100 : null,
                         rows: rows.map((r: any) => ({ ...r, mine: undefined, arten: kindMix(r.mine || []) })),
                         arten: kindOrder.map((k) => ({ key: k, label: kindLabel(k), n: kindCount[k] || 0,
                           pct: live.length ? Math.round((kindCount[k] || 0) / live.length * 100) : 0 })),
                         hourly: HRL, fbCount });

  // ── Mail bauen ────────────────────────────────────────────────────────────
  const brandKey = ((await agentMailSender(sb, "paul")) ? "paul" : "max");
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
    note: r.cl + (r.cl === 1 ? " Abschluss" : " Abschlüsse") + " aus " + r.n + " Vorgängen · " + Math.round(r.quote * 100) + " % Quote"
          + (HRL.on ? " · " + eur(r.hourRev) + " Stunden" : "")
          + (kindMix(r.mine || []) ? " · " + kindMix(r.mine || []) : ""),
    valuePct: Math.round(r.rev / maxRev * 100),
  });

  // Ertrag je Stunde: voller Umsatz durch die Stunden, die auch vergütet werden. Beide Teile getrennt
  // genannt, damit niemand den CPO-Anteil für die ganze Zahl hält (so steht es auch im Cockpit).
  const jeStd = HRL.on ? (total.paid > 0 ? gesamt / total.paid : null) : (total.paid > 0 ? total.rev / total.paid : null);
  const jeStdCpo = total.paid > 0 ? total.rev / total.paid : null;

  let inner = lead("<b>" + eur(gesamt) + "</b> " + (slot === "13" ? "stehen bis 13:00 Uhr auf der Uhr" : "sind heute zusammengekommen") + ". "
    + (HRL.on ? ("Davon " + eur(total.rev) + " aus Abschlüssen und " + eur(total.hourRev) + " aus " + hrs(total.paid) + " produktiver Zeit."
                 + (jeStd != null ? " Das sind <b>" + eur(jeStd) + "</b> je vergüteter Stunde, davon " + eur(jeStdCpo!) + " aus Abschlüssen." : ""))
              : (total.cl + (total.cl === 1 ? " Abschluss" : " Abschlüsse") + " aus " + total.n + " Vorgängen.")));
  inner += kacheln;
  if (resend) {
    inner += callout("Nachversand", "Dieser Tagesabschluss vom " + dmy(today) + " ging gestern Abend noch an die kleinere Runde. "
      + "Hier kommt er einmalig an alle. Ab heute läuft der Takt um 13:00 und 19:15 wieder normal.", "#2563eb");
  }

  if (kindOrder.length && live.length) {
    inner += '<tr><td style="padding:16px 16px 4px;font-size:13px;font-weight:bold;color:#0f2830;">'
      + 'Welche Fälle kamen herein, Anteil an ' + live.length + ' Vorgängen</td></tr>';
    kindOrder.forEach((k) => {
      const n2 = kindCount[k] || 0;
      const pct = Math.round(n2 / live.length * 100);
      inner += perfRow({ name: kindLabel(k), value: pct + " %", tone: k === "__na" ? "neutral" : "good",
        note: n2 + (n2 === 1 ? " Vorgang" : " Vorgänge"), valuePct: pct });
    });
  }

  if (liste.length) {
    inner += '<tr><td style="padding:16px 16px 4px;font-size:13px;font-weight:bold;color:#0f2830;">'
      + liste.length + ' Agenten am Telefon, nach Umsatz</td></tr>';
    liste.forEach((r, i) => {
      // Farbe sagt, wo jemand gegenueber dem Tagesschnitt steht — ohne die Ueberschrift „die Schwaechsten".
      const tone = r.rev === 0 ? "warn" : (r.rev >= schnitt ? "good" : "neutral");
      inner += zeile(r, tone, ["🥇", "🥈", "🥉"][i]);
    });
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
  inner += refLine((slot === "13"
    ? "Zwischenstand: Vorgänge bis 13:00 Uhr, Stunden anteilig bis 13:00 Uhr."
    : "Tagesabschluss um 19:15 Uhr, nach dem Ende der Spätschicht: alle Vorgänge des Tages, Stunden für den geplanten Tag.")
    + " In der Liste stehen alle Agenten am Telefon, sortiert nach Umsatz; grün heißt über dem Tagesschnitt."
    + (HRL.on ? " Je vergüteter Stunde = CPO plus Stundenvergütung geteilt durch die Stunden, die vergütet werden — Overhead und Tage ohne Vorgang zählen nicht mit." : ""));

  const html = shell(brand, titel, unter, inner);
  const subject = (isTest ? "[Test] " : "") + titel + " · " + eur(gesamt);
  if (body.html === true) return new Response(html, { headers: { ...cors, "Content-Type": "text/html; charset=utf-8" } });

  // ── Empfänger ─────────────────────────────────────────────────────────────
  let to: string[] = [];
  if (isTest) {
    to = [String(body.to || OWNER_MAIL)];
  } else {
    // Wer die Mail bekommt, richtet sich nach dem Tag des Versands, nicht nach dem Berichtstag.
    to = await empfaengerFuer(sb, sendeTag);
  }

  // Absender ist Paul, bei beiden Mandaten derselbe (Entscheidung 2026-09-28). Im Agenten-Register
  // gehoert ihm die Analyse: "Forecast gegen Ist, gelieferte Stunden je Projekt und Skill, Unter- und
  // Ueberdeckung". Anna beantwortet Fragen, sie verschickt keine Berichte. Max bleibt nur als Rueckfall.
  const sender = (await agentMailSender(sb, "paul")) || (await agentMailSender(sb, "max"));
  if (!sender) return json({ ok: false, error: "Kein Absender mit Postfach gefunden" }, 500);
  const results: any[] = [];
  for (const adr of to) {
    const r = await smtpSend(sender, adr, subject, html);
    results.push({ to: adr, ok: r.ok, error: r.error });
  }
  return json({ ok: results.every((r) => r.ok), slot, today, to, gesamt, cpo: total.rev, stunden: total.hourRev, agenten: rows.length, results });
});
