// Pauls Wächter über den HolidayCheck-Stundenabgleich. Einmal täglich um 19:25 Berliner Zeit,
// direkt nach dem Tagesabschluss — und NUR, wenn es etwas zu melden gibt. Lieber wenige Meldungen,
// die jemand liest. Empfänger ist allein info@mynaai.de; die beiden Tagesreports (hc-report) gehen
// weiter an alle drei.
//
// Geprüft wird:
//  1 Unterdeckung morgen        abrechenbarer Plan unter 90 % des Tagesziels
//  2 Unterdeckung Folgewoche    freitags: Plan der kommenden Woche unter 90 % des Wochenziels
//  3 Lücke im Schichtplan       Werktag ohne eine einzige Schicht in den nächsten 14 Tagen
//  4 Planhorizont endet         weniger als 10 Tage im Voraus geplant
//  5 Geplant, nichts geliefert  letzte volle Woche: im Plan, nichts protokolliert, keine Abwesenheit
//  6 Forecast fehlt             für die kommende Woche liegt für einen Skill kein Ziel vor
//
// Zu 5: die protokollierten Stunden kommen aus dem Wochen-Import des Auftraggebers und hinken dem
// Plan hinterher. Deshalb schaut diese Prüfung bewusst auf die letzte abgeschlossene Woche und nur
// dann, wenn für diese Woche überhaupt etwas importiert wurde — sonst meldet sie den Importrückstand
// statt eines echten Befunds.
//
// Cron alle 5 Minuten ohne Körper; Fenster und Sperre in cpo_report_log (slot 'hcwatch') verhindern
// Doppelmeldungen. {dry:true} rechnet nur, {mode:"test",to:"..."} schickt an eine Adresse.
// Deploy: supabase functions deploy hc-watch --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { agentBrand, shell, lead, callout, perfRow, button, refLine, PORTAL_URL } from "../_shared/agent_mail.ts";
import { smtpSend, agentMailSender } from "../_shared/agent_send.ts";
import { hcCompute, berlinNow, isoDay, addDays, daysBetween, isoWeek, eur, hrs, dmy, HC_PROJECT, HC_SKILLS } from "../_shared/hc_hours.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

const OWNER_MAIL = "info@mynaai.de";
const UNTER = 0.9;        // ab hier gilt es als Unterdeckung
const HORIZONT = 10;      // so viele Tage im Voraus sollte der Plan stehen

type Fund = { titel: string; text: string; ton: "bad" | "warn" | "neutral" };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* Cron ohne Koerper */ }

  const now = berlinNow();
  const mins = now.getHours() * 60 + now.getMinutes();
  const isTest = body.mode === "test" || !!body.to;
  const dry = body.dry === true;
  const forced = isTest || dry || body.force === true;
  if (!forced && !(mins >= 1165 && mins < 1170)) return json({ ok: true, skipped: "kein Zeitfenster" });

  const today = String(body.day || isoDay(now));
  if (!isTest && !dry) {
    const { error } = await admin.from("cpo_report_log").insert({ day: today, slot: "hcwatch" });
    if (error) return json({ ok: true, skipped: "heute schon gemeldet" });
  }

  const funde: Fund[] = [];
  const morgen = addDays(today, 1);

  // ── 1 Unterdeckung morgen ─────────────────────────────────────────────────
  // Verglichen wird "Woche bis morgen" gegen das anteilige Wochenziel. Ein einzelner Tag gegen ein
  // Wochenziel meldete an jedem Werktag ein Plus und an jedem Wochenende ein Minus (Befund 2026-09-30).
  const M = await hcCompute(admin, morgen, morgen, null);
  const mSkills = M.skills.filter((s) => s.ziel > 0);
  mSkills.forEach((s) => {
    const bis = (s as any).abrBis != null ? (s as any).abrBis : s.abr;
    if (bis < s.ziel * UNTER) {
      funde.push({
        titel: "Woche läuft unter Ziel: " + s.label, ton: "bad",
        text: "Bis einschließlich " + dmy(morgen) + " stehen " + hrs(bis) + " abrechenbar gegen ein anteiliges Wochenziel von "
          + hrs(s.ziel) + " — es fehlen " + hrs(s.ziel - bis)
          + (s.rate != null ? (" oder " + eur((s.ziel - bis) * s.rate)) : "") + ".",
      });
    }
  });
  if (!M.list.length) {
    funde.push({ titel: "Morgen steht niemand im Plan", ton: "bad", text: "Für den " + dmy(morgen) + " ist bei HolidayCheck keine einzige Schicht hinterlegt." });
  }

  // ── 2 Unterdeckung Folgewoche (freitags) ──────────────────────────────────
  if (now.getDay() === 5 || body.force === true) {
    const mo = addDays(today, 8 - (now.getDay() || 7));     // Montag der kommenden Woche
    const so = addDays(mo, 6);
    const W = await hcCompute(admin, mo, so, null);
    // Steht fuer die Woche ueberhaupt noch kein Plan, ist das die Meldung — nicht die Luecke zum Ziel.
    // Sonst kaeme dieselbe Sache zweimal, einmal als fehlender Plan und einmal als Unterdeckung.
    if (W.list.length) W.skills.filter((s) => s.ziel > 0).forEach((s) => {
      const bis = (s as any).abrBis != null ? (s as any).abrBis : s.abr;
      if (bis < s.ziel * UNTER) {
        funde.push({
          titel: "Kommende Woche unter Ziel: " + s.label, ton: "warn",
          text: "KW " + isoWeek(mo).kw + ": " + hrs(s.abr) + " geplant gegen " + hrs(s.ziel) + " Ziel, es fehlen " + hrs(s.ziel - s.abr)
            + (s.rate != null ? (" oder " + eur((s.ziel - s.abr) * s.rate)) : "") + ". Jetzt ist noch Zeit, das zu drehen.",
        });
      }
    });
  }

  // ── 3+4 Schichtplan: Lücken und Horizont ─────────────────────────────────
  const bis = addDays(today, 14);
  const { data: sh14 } = await admin.from("shift_assignments").select("work_date")
    .eq("project_id", HC_PROJECT).gt("work_date", today).lte("work_date", bis);
  const belegt: Record<string, boolean> = {};
  (sh14 || []).forEach((r: any) => { belegt[String(r.work_date).slice(0, 10)] = true; });
  const luecken = daysBetween(addDays(today, 1), bis).filter((ds) => {
    const dow = new Date(ds + "T00:00:00").getDay();
    return dow >= 1 && dow <= 5 && !belegt[ds];
  });
  if (luecken.length) {
    funde.push({
      titel: luecken.length === 1 ? "Ein Werktag ohne Schichtplan" : luecken.length + " Werktage ohne Schichtplan", ton: "warn",
      text: luecken.slice(0, 8).map(dmy).join(", ") + (luecken.length > 8 ? " und " + (luecken.length - 8) + " weitere" : "")
        + ". Ohne Plan gibt es an diesen Tagen nichts abzurechnen.",
    });
  } else {
    const letzter = Object.keys(belegt).sort().pop() || today;
    const tageVoraus = daysBetween(addDays(today, 1), letzter).length;
    if (tageVoraus < HORIZONT) {
      funde.push({
        titel: "Der Plan reicht nicht weit genug", ton: "warn",
        text: "Geplant ist bis " + dmy(letzter) + ", das sind " + tageVoraus + " Tage im Voraus. Unter " + HORIZONT + " Tagen wird es eng für Urlaub und Umplanung.",
      });
    }
  }

  // ── 5 Geplant, aber nichts protokolliert (letzte volle Woche) ────────────
  const lastMon = addDays(today, -((new Date(today + "T00:00:00").getDay() || 7) - 1) - 7);
  const lastSun = addDays(lastMon, 6);
  const { count: istCount } = await admin.from("daily_hours").select("employee_id", { count: "exact", head: true })
    .eq("project_id", HC_PROJECT).gte("work_date", lastMon).lte("work_date", lastSun);
  if (istCount && istCount > 0) {
    const L = await hcCompute(admin, lastMon, lastSun, null);
    const stumm = L.list.filter((r: any) => r.netto > 3 && r.ist <= 0 && r.abr > 0);
    if (stumm.length) {
      funde.push({
        titel: stumm.length === 1 ? "Eine Person ohne protokollierte Stunde" : stumm.length + " Personen ohne protokollierte Stunde", ton: "bad",
        text: "In KW " + isoWeek(lastMon).kw + " im Plan, aber im System des Auftraggebers keine einzige Stunde: "
          + stumm.map((r: any) => r.name + " (" + hrs(r.netto) + " geplant)").join(", ")
          + ". Entweder fehlt eine Abwesenheit oder die Stunden sind nicht angekommen.",
      });
    }
  }

  // ── 6 Forecast fehlt für die kommende Woche ──────────────────────────────
  const nextMon = addDays(today, 8 - (new Date(today + "T00:00:00").getDay() || 7));
  const w = isoWeek(nextMon);
  const { data: fc } = await admin.from("report_forecast").select("skill")
    .eq("project_id", HC_PROJECT).eq("year", w.year).eq("kw", w.kw);
  const da = new Set((fc || []).map((r: any) => String(r.skill || "").toLowerCase()));
  const fehlt = HC_SKILLS.filter((s) => !da.has(s));
  if (fehlt.length) {
    funde.push({
      titel: "Kein Ziel für KW " + w.kw, ton: "warn",
      text: "Für " + fehlt.map((s) => s === "sales" ? "Sales" : "Support").join(" und ") + " liegt kein Forecast vor. Ohne Ziel lässt sich die Lücke nicht rechnen.",
    });
  }

  if (dry) return json({ ok: true, today, funde });
  if (!funde.length) return json({ ok: true, today, funde: 0, note: "nichts zu melden" });

  // ── Mail ──────────────────────────────────────────────────────────────────
  const brand = await agentBrand(admin, "paul");
  let inner = lead(funde.length === 1 ? "Eine Auffälligkeit beim HolidayCheck-Stundenabgleich." : funde.length + " Auffälligkeiten beim HolidayCheck-Stundenabgleich.");
  funde.forEach((f) => { inner += callout(f.titel, f.text, f.ton === "bad" ? "#dc2626" : "#d97706"); });
  inner += button(PORTAL_URL + "?goto=hcstunden", "HC Stundenabgleich öffnen", brand.accent);
  inner += refLine("Geprüft um 19:25 Uhr, nur wenn es etwas zu melden gibt. Grundlage ist der Schichtplan mit den hinterlegten abrechenbaren Anteilen, "
    + "das Ziel kommt aus dem Wochen-Forecast des Auftraggebers.");
  const html = shell(brand, "HolidayCheck: " + (funde.length === 1 ? "eine Auffälligkeit" : funde.length + " Auffälligkeiten"), dmy(today) + " · Stundenabgleich", inner);
  const subject = (isTest ? "[Test] " : "") + "HolidayCheck: " + (funde.length === 1 ? "eine Auffälligkeit" : funde.length + " Auffälligkeiten") + " am " + dmy(today);
  if (body.html === true) return new Response(html, { headers: { ...cors, "Content-Type": "text/html; charset=utf-8" } });

  const to: string[] = [isTest ? String(body.to || OWNER_MAIL) : OWNER_MAIL];
  const sender = (await agentMailSender(admin, "paul")) || (await agentMailSender(admin, "max"));
  if (!sender) return json({ ok: false, error: "Kein Absender mit Postfach gefunden" }, 500);
  const results: any[] = [];
  for (const adr of to) { const r = await smtpSend(sender, adr, subject, html); results.push({ to: adr, ok: r.ok, error: r.error }); }
  return json({ ok: results.every((r) => r.ok), today, funde: funde.length, to, results });
});
