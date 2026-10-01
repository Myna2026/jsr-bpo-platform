// Pauls HolidayCheck-Report, zweimal am Tag: 13:00 der Zwischenstand, 19:15 der Tagesabschluss.
// Gleicher Aufbau wie der Giganetz-Report (cpo-report), nur ohne CPO: bei HolidayCheck zaehlen
// Stunden. Je Skill die abrechenbaren Stunden und der Umsatz daraus, dazu das Ziel aus dem Forecast
// und die Luecke. Empfaenger: info@mynaai.de, Thorsten, Rajner.
//
// Gerechnet wird wie im Leitstand ("HC Stundenabgleich"), eine gemeinsame Datei: _shared/hc_hours.ts.
//  - Abrechenbar = Schichtplan netto (Pausen raus), abzueglich Urlaub/Krankheit, mal dem Anteil der Person.
//  - Um 13:00 zaehlt die bis dahin gelaufene Schichtzeit anteilig, abends der volle geplante Tag.
//    Spaeter als 19:15 aendert sich nichts mehr: die Grundlage ist der Plan, nicht die Stempelung.
//  - Das Ziel kommt aus report_forecast und liegt nur je Woche vor; fuer einen einzelnen Tag wird es
//    gleichmaessig verteilt. Solange die Forecast-Frage mit HolidayCheck offen ist, steht das auch
//    in der Mail. Ist sie geklaert, aendert sich nur die Zahl, nicht der Aufbau.
//
// Cron ruft alle 5 Minuten ohne Koerper auf; die Function feuert nur in ihrem Fenster und schreibt den
// Anspruch VOR dem Senden nach cpo_report_log (Schluessel Tag+Fenster, Slots 'hc13'/'hc19') — so geht
// nichts doppelt raus (Falle „Dispatcher-Rennen").
// Aufrufe: {mode:"send", slot:"13"|"19"} erzwingt einen Lauf · {mode:"test", to:"..."} eine Testmail
// an genau eine Adresse · {dry:true} rechnet nur · {html:true} gibt die Mail als Seite zurueck.
// Deploy: supabase functions deploy hc-report --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { agentBrand, shell, lead, tiles, perfRow, callout, button, refLine, PORTAL_URL } from "../_shared/agent_mail.ts";
import { smtpSend, agentMailSender } from "../_shared/agent_send.ts";
import { hcCompute, berlinNow, isoDay, eur, hrs, dmy, HC_PROJECT } from "../_shared/hc_hours.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

const OWNER_MAIL = "info@mynaai.de";
const FALLBACK_TO = ["consulting@25hrs.net", "r.gore@tiramu.de"];   // Thorsten, Rajner
// Bewusst getrennt vom Giganetz-Report (Entscheidung 2026-09-28): dort sind Ylli und Shkurte
// dazugekommen, hier nicht. HolidayCheck ist Edis Mandat — kommt hier jemand dazu, dann Edi.

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* Cron ohne Koerper */ }

  const now = berlinNow();
  const mins = now.getHours() * 60 + now.getMinutes();
  const isTest = body.mode === "test" || !!body.to;
  const dry = body.dry === true;
  const forced = typeof body.slot === "string";
  const forcedRun = forced || isTest || dry;
  // Fenster in Berliner Zeit, je fuenf Minuten breit (Cron alle 5 Minuten).
  const fenster = (mins >= 780 && mins < 785) ? "13" : (mins >= 1155 && mins < 1160) ? "19" : null;
  const slot: string = forced ? String(body.slot) : (fenster || "");
  if (!slot) return json({ ok: true, skipped: "kein Zeitfenster", berlin: now.toISOString() });
  const today = String(body.day || isoDay(now));
  const cut = slot === "13" ? 13 * 60 : null;      // null = der ganze geplante Tag

  if (!isTest && !dry) {
    const { error } = await admin.from("cpo_report_log").insert({ day: today, slot: "hc" + slot });
    if (error) return json({ ok: true, skipped: "schon versendet", day: today, slot });
  }

  // Sa/So nur, wenn ueberhaupt jemand im Plan steht.
  const wochenende = now.getDay() === 0 || now.getDay() === 6;
  if (wochenende && !forcedRun) {
    const { count } = await admin.from("shift_assignments").select("employee_id", { count: "exact", head: true })
      .eq("project_id", HC_PROJECT).eq("work_date", today);
    if (!count) return json({ ok: true, skipped: "Wochenende ohne Schicht" });
  }

  const R = await hcCompute(admin, today, today, cut);
  if (dry) return json({ ok: true, slot, today, total: R.total, skills: R.skills.map((s) => ({ ...s, rows: s.rows.length })), ohneZiel: R.ohneZiel });

  // ── Mail bauen ────────────────────────────────────────────────────────────
  const brandKey = (await agentMailSender(admin, "paul")) ? "paul" : "max";
  const brand = await agentBrand(admin, brandKey);
  const titel = slot === "13" ? "HolidayCheck, Zwischenstand 13:00" : "HolidayCheck, Tagesabschluss";
  const unter = dmy(today) + " · HolidayCheck, Sales und Support" + (slot === "13" ? " · Stand 13:00 Uhr" : "");

  const aktive = R.skills.filter((s) => s.rows.length > 0 || s.ziel > 0);
  const kacheln = tiles([
    { big: eur(R.total.eur), label: "Umsatz aus Stunden", sub: hrs(R.total.abr) + " abrechenbar" },
    ...aktive.map((s) => ({ big: eur(s.eur || 0), label: s.label, sub: hrs(s.abr) + (s.rate != null ? (" × " + eur(s.rate)) : "") })),
  ]);

  let inner = lead("<b>" + eur(R.total.eur) + "</b> " + (slot === "13" ? "stehen bis 13:00 Uhr auf der Uhr" : "sind heute zusammengekommen") + ". "
    + "Das sind " + hrs(R.total.abr) + " abrechenbare Zeit aus " + hrs(R.total.netto) + " Plan netto"
    + (R.total.abw > 0 ? (", nach " + hrs(R.total.abw) + " Abwesenheit") : "") + ".");
  inner += kacheln;

  // Je Skill: Ziel, Ist und die Luecke — IMMER als "Woche bis heute". Das Ziel liegt je Woche vor;
  // ein Tageswert dagegen zu stellen erzeugt an jedem Werktag ein Plus und am Wochenende ein Minus,
  // ohne dass sich an der Lage etwas geaendert haette (Befund 2026-09-30).
  inner += '<tr><td style="padding:16px 16px 4px;font-size:13px;font-weight:bold;color:#0f2830;">Woche bis heute: Ziel und abrechenbarer Plan je Skill</td></tr>';
  aktive.forEach((s) => {
    const bis = (s as any).abrBis != null ? (s as any).abrBis : s.abr;
    const pct = s.ziel > 0 ? Math.round(bis / s.ziel * 100) : 0;
    const tone = s.ziel <= 0 ? "neutral" : (pct >= 98 ? "good" : (pct >= 90 ? "warn" : "bad"));
    const note = s.ziel > 0
      ? (hrs(bis) + " abrechenbar von " + hrs(s.ziel) + " Ziel seit Montag · " + (s.luecke! >= 0 ? "+" : "") + hrs(s.luecke!) + (s.lueckeEur != null ? (" · " + (s.lueckeEur >= 0 ? "+" : "") + eur(s.lueckeEur)) : ""))
      : "kein Forecast hinterlegt, deshalb kein Ziel";
    inner += perfRow({ name: s.label, value: eur(s.eur || 0), tone, note, valuePct: Math.min(100, pct) });
  });

  if (R.total.abw > 0) {
    const wer = R.list.filter((r: any) => r.abw > 0).map((r: any) => r.name + " (" + hrs(r.abw) + ")");
    inner += callout("Abwesenheit kürzt den Tag", hrs(R.total.abw) + " fallen weg: " + wer.join(", ") + ".", "#d97706");
  }
  // Der Forecast deckelt: was darueber hinaus geleistet wurde, bezahlt HolidayCheck nicht. Das muss
  // in der Mail stehen, sonst sieht eine gekappte Stunde aus wie eine nicht geleistete.
  const gekappt = R.skills.reduce((a: number, s: any) => a + (s.gekappt || 0), 0);
  if (gekappt > 0.05) {
    const wo = (R as any).kapTage.map((k: any) => dmy(k.ds) + " " + (k.skill === "sales" ? "Sales" : "Support") + " " + hrs(k.weg));
    inner += callout("Über dem Forecast, deshalb nicht abrechenbar",
      hrs(gekappt) + " liegen über dem Tagesforecast und zählen nicht: " + wo.slice(0, 6).join(", ")
      + (wo.length > 6 ? " und " + (wo.length - 6) + " weitere" : "")
      + ". Hat HolidayCheck die Stunden angefordert, im Leitstand unter Zusatzstunden eintragen, dann zählen sie wieder.", "#d97706");
  }
  if ((R as any).extras && (R as any).extras.length) {
    const ex = (R as any).extras;
    inner += callout("Zusatzstunden berücksichtigt",
      ex.map((e: any) => dmy(e.ds) + " " + (e.skill === "sales" ? "Sales" : "Support") + " " + hrs(e.h) + (e.reason ? " (" + e.reason + ")" : "")).join(", ")
      + ". Diese Stunden heben den Forecast-Deckel des jeweiligen Tages.", "#2563eb");
  }
  if (R.trainNames.length) {
    inner += callout("Schulung läuft", "Heute läuft " + R.trainNames.join(", ") + ". Wer dafür auf 0 Prozent steht, zählt an diesem Tag nicht mit.", "#2563eb");
  }
  if (R.offenOverhead.length) {
    inner += callout("Ohne hinterlegten Anteil",
      R.offenOverhead.join(", ") + " zählt voll mit, weil kein abrechenbarer Anteil hinterlegt ist. Im Leitstand unter Abrechenbare Anteile einstellen.", "#d97706");
  }
  if (R.ohneZiel.length) {
    inner += callout("Kein Ziel hinterlegt", "Für " + R.ohneZiel.join(" und ") + " liegt für diese Woche kein Forecast vor. Die Lücke lässt sich nicht berechnen.", "#d97706");
  }
  if (!R.list.length) {
    inner += callout("Niemand im Plan", "Für heute steht bei HolidayCheck keine Schicht im Plan.", "#dc2626");
  }

  inner += button(PORTAL_URL + "?goto=hcstunden", "HC Stundenabgleich öffnen", brand.accent);
  inner += refLine((slot === "13"
    ? "Zwischenstand: die bis 13:00 Uhr gelaufene Schichtzeit, anteilig gerechnet."
    : "Tagesabschluss: der ganze geplante Tag. Grundlage ist der Schichtplan, nicht die Stempelung: später ändert sich daran nichts mehr.")
    + " Abrechenbar = Schichtplan netto, abzüglich Urlaub und Krankheit, je Person mit ihrem hinterlegten Anteil,"
    + " höchstens jedoch der Forecast des Tages: HolidayCheck bezahlt den kleineren der beiden Werte."
    + " Angeforderte Zusatzstunden heben diese Grenze für den betroffenen Tag."
    + " Die Kacheln zeigen den Tag, Ziel und Lücke dagegen die Woche seit Montag: der Forecast ist ein Wochenwert,"
    + " und ein einzelner Tag dagegen gestellt ergibt keine belastbare Aussage. Das anteilige Wochenziel richtet sich"
    + " nach dem geplanten Volumen der bisherigen Tage, am Sonntag steht damit genau das Wochenziel.");

  const html = shell(brand, titel, unter, inner);
  const subject = (isTest ? "[Test] " : "") + titel + " · " + eur(R.total.eur);
  if (body.html === true) return new Response(html, { headers: { ...cors, "Content-Type": "text/html; charset=utf-8" } });

  let to: string[] = [];
  if (isTest) {
    to = [String(body.to || OWNER_MAIL)];
  } else {
    const { data: us } = await admin.from("app_users").select("user_id,full_name").or("full_name.ilike.%Thorsten%,full_name.ilike.%Rajner%");
    const mails: string[] = [];
    for (const u of us || []) {
      const { data: au } = await admin.auth.admin.getUserById((u as any).user_id);
      const m = au?.user?.email; if (m) mails.push(m);
    }
    to = [...new Set([OWNER_MAIL, ...(mails.length ? mails : FALLBACK_TO)])];
  }

  const sender = (await agentMailSender(admin, "paul")) || (await agentMailSender(admin, "max"));
  if (!sender) return json({ ok: false, error: "Kein Absender mit Postfach gefunden" }, 500);
  const results: any[] = [];
  for (const adr of to) {
    const r = await smtpSend(sender, adr, subject, html);
    results.push({ to: adr, ok: r.ok, error: r.error });
  }
  return json({ ok: results.every((r) => r.ok), slot, today, to, stunden: R.total.abr, umsatz: R.total.eur, ziel: R.total.ziel, results });
});
