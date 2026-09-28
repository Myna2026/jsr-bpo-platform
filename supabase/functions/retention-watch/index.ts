// Annas Wächter über das Retention Overview. Einmal täglich um 19:20 Berliner Zeit, direkt nach dem
// Tagesabschluss — und NUR, wenn es etwas zu melden gibt. Lieber wenige Meldungen, die jemand liest.
// Empfänger ist allein info@mynaai.de; die beiden Tagesreports (cpo-report) gehen weiter an alle drei.
//
// Geprüft wird (vom User am 2026-09-28 so festgelegt):
//  1 Einbruch bei den Abschlüssen   Tag unter 50 % des Schnitts der letzten fünf Arbeitstage
//  2 Jemand erfasst nichts mehr     im Plan, nicht abwesend, heute null Vorgänge, war zuletzt aktiv
//  3 Quote fällt                    Tagesquote unter 60 % des Schnitts (erst ab 20 Vorgängen)
//  4 Tag reißt aus                  Umsatz weicht über 40 % vom Schnitt ab, nach oben wie unten
//  5 Schichtplan                    Tag ohne Plan, Erfassung ohne Planzeile, freitags der Planhorizont
//  6 Stornoquote                    über 5 % der Abschlüsse der letzten sieben Tage storniert
//  7 Anteil Rabattstufe 2           über 70 % bei mindestens zehn Abschlüssen
//  8 Widerspruch Plan gegen Erfassung   krank oder im Urlaub gemeldet und trotzdem erfasst
//
// Zu 4: die Hochrechnung selbst reißt nur untertags aus. Abends ist der Tag entschieden, deshalb
// vergleicht der Wächter das Ergebnis mit dem Schnitt — dieselbe Frage, nur mit harten Zahlen.
//
// Cron alle 5 Minuten ohne Körper; das Fenster und die Sperre in cpo_report_log (slot 'watch')
// verhindern Doppelmeldungen. {dry:true} rechnet nur, {mode:"test",to:"..."} schickt an eine Adresse.
// Deploy: supabase functions deploy retention-watch --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { agentBrand, shell, lead, callout, perfRow, button, refLine, PORTAL_URL } from "../_shared/agent_mail.ts";
import { smtpSend, agentMailSender } from "../_shared/agent_send.ts";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

const PROJ = "proj_gn_e5f6a7b8", SKILL = "retention";
const OWNER_MAIL = "info@mynaai.de";

const AGENT_POS = ["Agent", "Senior Agent", "ASP", "Supervisor"];   // Kategorie "agent" laut docs/fachmodell
function istAgent(emp: any) { return !!emp && AGENT_POS.indexOf(String(emp.position || "").trim()) >= 0; }
function berlinNow() { return new Date(new Date().toLocaleString("en-US", { timeZone: "Europe/Berlin" })); }
function iso(d: Date) { return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); }
function eur(v: number) { return (Math.round((v || 0) * 100) / 100).toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + " €"; }
function dmy(ds: string) { const [y, m, d] = ds.split("-"); return Number(d) + "." + Number(m) + "." + y; }
function pct(v: number) { return Math.round(v * 100) + " %"; }
function absOn(emp: any, ds: string) {
  for (const a of ((emp && emp.absences) || [])) {
    const f = String(a.from || "").slice(0, 10); if (!f) continue;
    const t = String(a.to || f).slice(0, 10);
    if (ds >= f && ds <= t) return String(a.type || "abwesend");
  }
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* Cron */ }
  const now = berlinNow();
  const mins = now.getHours() * 60 + now.getMinutes();
  const isTest = body.mode === "test" || !!body.to;
  const dry = body.dry === true;
  const forced = isTest || dry || body.force === true;
  const forcedRun = forced;
  if (!forced && !(mins >= 1160 && mins < 1165)) return json({ ok: true, skipped: "kein Zeitfenster" });

  const today = String(body.day || iso(now));
  if (!isTest && !dry) {
    const { error } = await sb.from("cpo_report_log").insert({ day: today, slot: "watch" });
    if (error) return json({ ok: true, skipped: "heute schon gemeldet" });
  }

  // Sa/So nur, wenn tatsaechlich erfasst wurde — sonst bleibt der Posteingang still.
  const wochenende = now.getDay() === 0 || now.getDay() === 6;
  if (wochenende && !forcedRun) {
    const { count } = await sb.from("cpo_entries").select("id", { count: "exact", head: true })
      .eq("project_id", PROJ).eq("skill", SKILL).eq("work_date", today).is("cancelled_at", null);
    if (!count) return json({ ok: true, skipped: "Wochenende ohne Erfassung" });
  }

  // ── Daten: 14 Tage zurück reichen für alle Vergleiche ─────────────────────
  const von = (() => { const d = new Date(today + "T00:00:00"); d.setDate(d.getDate() - 14); return iso(d); })();
  const [{ data: ents }, { data: shifts }] = await Promise.all([
    sb.from("cpo_entries").select("employee_id,work_date,is_close,cpo_amount,discount_level,cancelled_at")
      .eq("project_id", PROJ).eq("skill", SKILL).gte("work_date", von).lte("work_date", today),
    sb.from("shift_assignments").select("employee_id,work_date,net_hours")
      .eq("project_id", PROJ).eq("skill", SKILL).gte("work_date", von),
  ]);
  const all = ents || [], sh = shifts || [];
  const ids = [...new Set([...all.map((r: any) => r.employee_id), ...sh.map((s: any) => s.employee_id)])];
  const { data: emps } = ids.length ? await sb.from("employees").select("id,first_name,last_name,position,absences").in("id", ids) : { data: [] as any[] };
  const empBy: Record<string, any> = {}; (emps || []).forEach((e: any) => { empBy[e.id] = e; });
  const nameOf = (id: string) => { const e = empBy[id] || {}; return ((e.first_name || "") + " " + (e.last_name || "")).trim() || "Unbekannt"; };

  const live = all.filter((r: any) => !r.cancelled_at);
  const ofDay = (ds: string) => live.filter((r: any) => String(r.work_date).slice(0, 10) === ds);
  const heute = ofDay(today);
  // Vergleichsbasis: die letzten fünf Tage VOR heute, an denen überhaupt erfasst wurde
  const tageMitDaten = [...new Set(live.map((r: any) => String(r.work_date).slice(0, 10)))].filter((d) => d < today).sort();
  const basis = tageMitDaten.slice(-5);
  const bTage = basis.length;
  const bCl = basis.reduce((a, d) => a + ofDay(d).filter((r: any) => r.is_close).length, 0);
  const bN = basis.reduce((a, d) => a + ofDay(d).length, 0);
  const bRev = basis.reduce((a, d) => a + ofDay(d).filter((r: any) => r.is_close).reduce((x: number, r: any) => x + (Number(r.cpo_amount) || 0), 0), 0);
  const schnittCl = bTage ? bCl / bTage : 0, schnittRev = bTage ? bRev / bTage : 0, schnittQuote = bN ? bCl / bN : 0;

  const hCl = heute.filter((r: any) => r.is_close).length;
  const hN = heute.length;
  const hRev = heute.filter((r: any) => r.is_close).reduce((a: number, r: any) => a + (Number(r.cpo_amount) || 0), 0);
  const hQuote = hN ? hCl / hN : 0;

  type Fund = { titel: string; text: string; ton: "bad" | "warn" };
  const funde: Fund[] = [];

  // 1 Einbruch bei den Abschlüssen
  if (bTage >= 3 && schnittCl >= 2 && hCl < schnittCl * 0.5) {
    funde.push({ titel: "Einbruch bei den Abschlüssen", ton: "bad",
      text: "Heute " + hCl + " Abschlüsse gegen einen Schnitt von " + (Math.round(schnittCl * 10) / 10) + " aus den letzten " + bTage + " Arbeitstagen." });
  }
  // 4 Tag reißt aus (Umsatz)
  if (bTage >= 3 && schnittRev >= 100) {
    const ab = (hRev - schnittRev) / schnittRev;
    // Verglichen wird CPO gegen CPO. Die Stundenvergütung haengt am Schichtplan, nicht an der
    // Leistung des Tages, und wuerde den Ausschlag verwaessern — deshalb steht sie hier bewusst nicht drin.
    if (Math.abs(ab) > 0.4) funde.push({ titel: ab < 0 ? "CPO-Umsatz weit unter dem Schnitt" : "CPO-Umsatz weit über dem Schnitt", ton: ab < 0 ? "bad" : "warn",
      text: "Heute " + eur(hRev) + " CPO gegen " + eur(schnittRev) + " im Schnitt, das sind " + (ab > 0 ? "+" : "") + Math.round(ab * 100) + " %. Die Stundenvergütung bleibt hier aussen vor." });
  }
  // 3 Quote fällt
  if (hN >= 20 && schnittQuote > 0 && hQuote < schnittQuote * 0.6) {
    funde.push({ titel: "Abschlussquote fällt", ton: "warn",
      text: "Heute " + pct(hQuote) + " aus " + hN + " Vorgängen, im Schnitt " + pct(schnittQuote) + "." });
  }
  // 2 Jemand erfasst nichts mehr
  const heuteAktiv = new Set(heute.map((r: any) => r.employee_id));
  const imPlanHeute = [...new Set(sh.filter((s: any) => String(s.work_date).slice(0, 10) === today).map((s: any) => s.employee_id))];
  const zuletztAktiv = new Set(basis.flatMap((d) => ofDay(d).map((r: any) => r.employee_id)));
  // Nur Fall-Bearbeiter: Teamleitung, Trainer, QM und Projektleitung stehen im Plan, erfassen aber
  // keine Cases — sie dürfen hier nicht auftauchen, auch nicht nach einem einzelnen Eintrag.
  const stumm = imPlanHeute.filter((id) => istAgent(empBy[id]) && !heuteAktiv.has(id) && zuletztAktiv.has(id) && !absOn(empBy[id], today));
  if (stumm.length) {
    funde.push({ titel: stumm.length === 1 ? "Ein Agent hat heute nichts erfasst" : stumm.length + " Agenten haben heute nichts erfasst", ton: "bad",
      text: stumm.map(nameOf).join(", ") + " " + (stumm.length === 1 ? "steht" : "stehen") + " im Plan, ohne Abwesenheit, und " + (stumm.length === 1 ? "hat" : "haben") + " zuletzt regelmäßig erfasst." });
  }
  // 5 Schichtplan
  const planHeute = imPlanHeute.length;
  if (hN > 0 && planHeute === 0) {
    funde.push({ titel: "Kein Schichtplan für heute", ton: "bad",
      text: "Es wurde erfasst, aber für den " + dmy(today) + " steht keine einzige Schicht im Plan. Die Stundenvergütung rechnet deshalb mit dem Rückfallwert." });
  } else {
    const ohnePlan = [...heuteAktiv].filter((id) => istAgent(empBy[id]) && !imPlanHeute.includes(id));
    if (ohnePlan.length) funde.push({ titel: "Erfassung ohne Schicht im Plan", ton: "warn",
      text: ohnePlan.map(nameOf).join(", ") + ": heute erfasst, aber nicht im Plan. Für " + (ohnePlan.length === 1 ? "diesen Tag" : "diese Tage") + " hängt die Stundenvergütung an einer Annahme." });
  }
  if (now.getDay() === 5) {   // freitags: reicht der Plan in die nächste Woche?
    const planBis = sh.map((s: any) => String(s.work_date).slice(0, 10)).sort().slice(-1)[0] || today;
    let wt = 0; const d = new Date(today + "T00:00:00");
    while (iso(d) < planBis) { d.setDate(d.getDate() + 1); const w = d.getDay(); if (w > 0 && w < 6) wt++; }
    if (wt < 5) funde.push({ titel: "Der Schichtplan reicht nicht weit genug", ton: "warn",
      text: "Der Plan endet am " + dmy(planBis) + ", das sind noch " + wt + " Werktage. Danach fehlt die Grundlage für Hochrechnung und Stundenvergütung." });
  }
  // 6 Stornoquote der letzten sieben Tage
  const sieben = (() => { const d = new Date(today + "T00:00:00"); d.setDate(d.getDate() - 6); return iso(d); })();
  const w = all.filter((r: any) => String(r.work_date).slice(0, 10) >= sieben);
  const wCl = w.filter((r: any) => r.is_close);
  const wStorno = wCl.filter((r: any) => r.cancelled_at);
  if (wCl.length >= 10 && wStorno.length / wCl.length > 0.05) {
    funde.push({ titel: "Stornoquote über fünf Prozent", ton: "bad",
      text: wStorno.length + " von " + wCl.length + " Abschlüssen der letzten sieben Tage storniert (" + pct(wStorno.length / wCl.length) + "). Storno schreibt Umsatz rückwirkend ab." });
  }
  // 7 Anteil Rabattstufe 2
  const bezug = heute.filter((r: any) => r.is_close).length >= 10 ? heute.filter((r: any) => r.is_close) : live.filter((r: any) => r.is_close && String(r.work_date).slice(0, 10) >= sieben);
  const l2 = bezug.filter((r: any) => Number(r.discount_level) === 2).length;
  if (bezug.length >= 10 && l2 / bezug.length > 0.7) {
    funde.push({ titel: "Rabattstufe 2 dominiert", ton: "warn",
      text: l2 + " von " + bezug.length + " Abschlüssen auf Stufe 2 (" + pct(l2 / bezug.length) + "). Jede Stufe-2-Buchung bringt den niedrigeren CPO." });
  }
  // 8 Widerspruch Plan gegen Erfassung
  const widerspruch: string[] = [];
  [...new Set(live.filter((r: any) => String(r.work_date).slice(0, 10) >= sieben).map((r: any) => r.employee_id + "|" + String(r.work_date).slice(0, 10)))]
    .forEach((k) => { const [id, ds] = k.split("|"); const a = absOn(empBy[id], ds); if (a) widerspruch.push(nameOf(id) + " am " + dmy(ds) + " (" + a + ")"); });
  if (widerspruch.length) {
    funde.push({ titel: "Abwesend gemeldet und trotzdem erfasst", ton: "bad",
      text: widerspruch.slice(0, 6).join(" · ") + (widerspruch.length > 6 ? " und " + (widerspruch.length - 6) + " weitere" : "")
        + ". Entweder fehlt die Abwesenheit im System oder sie ist falsch eingetragen — beides verfälscht die Stundenvergütung." });
  }

  if (dry) return json({ ok: true, today, funde, kennzahlen: { hN, hCl, hRev, schnittCl, schnittRev, schnittQuote, bTage } });
  if (!funde.length) return json({ ok: true, today, funde: 0, note: "nichts zu melden" });

  // ── Mail ──────────────────────────────────────────────────────────────────
  const brandKey = ((await agentMailSender(sb, "anna")) ? "anna" : "max");
  const brand = await agentBrand(sb, brandKey);
  let inner = lead(funde.length === 1 ? "Eine Auffälligkeit im Retention Overview." : funde.length + " Auffälligkeiten im Retention Overview.");
  funde.forEach((f) => { inner += callout(f.titel, f.text, f.ton === "bad" ? "#dc2626" : "#d97706"); });
  inner += '<tr><td style="padding:14px 16px 2px;font-size:12px;color:#5b6b70;">Zum Vergleich: heute ' + hCl + " Abschlüsse aus " + hN
        + " Vorgängen (" + pct(hQuote) + "), " + eur(hRev) + " CPO-Umsatz. Schnitt der letzten " + bTage + " Arbeitstage: "
        + (Math.round(schnittCl * 10) / 10) + " Abschlüsse, " + eur(schnittRev) + ".</td></tr>";
  inner += button(PORTAL_URL + "?goto=cpotrack", "Retention Overview öffnen", brand.accent);
  inner += refLine("Gemeldet wird nur, wenn etwas auffällt. Schwellen: Abschlüsse unter der Hälfte des Schnitts, Quote unter 60 Prozent davon, Umsatz mehr als 40 Prozent daneben, Storno über 5 Prozent, Stufe 2 über 70 Prozent.");

  const html = shell(brand, "Retention: " + (funde.length === 1 ? "eine Auffälligkeit" : funde.length + " Auffälligkeiten"), dmy(today) + " · Deutsche GigaNetz, Retention", inner);
  const subject = (isTest ? "[Test] " : "") + "Retention: " + (funde.length === 1 ? "eine Auffälligkeit" : funde.length + " Auffälligkeiten") + " am " + dmy(today);

  // Nur an den Eigentümer (User, 2026-09-28): die zwei Tagesreports gehen an alle drei, die
  // Auffälligkeiten nur an ihn — sonst landen Einzelfälle über Agenten im Verteiler.
  const to: string[] = [isTest ? String(body.to || OWNER_MAIL) : OWNER_MAIL];
  const sender = (await agentMailSender(sb, "anna")) || (await agentMailSender(sb, "max"));
  if (!sender) return json({ ok: false, error: "Kein Absender mit Postfach" }, 500);
  const results: any[] = [];
  for (const adr of to) { const r = await smtpSend(sender, adr, subject, html); results.push({ to: adr, ok: r.ok, error: r.error }); }
  return json({ ok: results.every((r) => r.ok), today, funde: funde.map((f) => f.titel), to, results });
});
