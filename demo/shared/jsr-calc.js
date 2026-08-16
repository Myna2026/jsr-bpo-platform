/* ════════════════════════════════════════════════════════════════════════════
 * TIVE 360° — GETEILTE RECHENKERNE (hr.html + mitarbeiter.html)
 * ────────────────────────────────────────────────────────────────────────────
 * EINE Wahrheit für Rechnungen, die früher in beiden Portalen doppelt lagen und
 * auseinanderliefen. Reine Funktionen (Eingabe → Wert), kein DOM/React/Supabase.
 * Wird von beiden Portalen per <script src="shared/jsr-calc.js?v=__BUILD_ID__">
 * eingebunden und über window.JSRCalc genutzt.
 *
 * Prüfung: scripts/checks/sharedcheck.js (im Deploy) parst diese Datei und rechnet
 * die bekannten Urlaubs-Beispiele durch — Änderungen, die die Regel brechen,
 * blockieren den Deploy.
 * ════════════════════════════════════════════════════════════════════════════ */
(function (global) {
  'use strict';

  function num(v, d) { v = Number(v); return isFinite(v) ? v : d; }
  function startDateOf(emp) {
    return (emp && emp.contract && emp.contract.start) || (emp && emp.contract_start) || (emp && emp.hire_date) || '';
  }
  function toDate(ref) {
    if (!ref) return new Date();
    if (typeof ref === 'string') return new Date(ref.length === 7 ? ref + '-01' : ref);
    return ref;                                  // bereits ein Date
  }

  /* Urlaubsanspruch nach KALENDERJAHR (nicht Eintrittsdatum/Jahrestag):
   *   Eintrittsjahr  = year1_days anteilig ab dem Monat NACH Eintritt (Dez → 0)
   *   Folgejahre     = year2_days voll (+ Betriebszugehörigkeits-Staffel)
   *   Austrittsjahr  = anteilig bis einschließlich Austrittsmonat
   *   Rundung        = round(x*2)/2  (halbe Tage)
   * cfg  = { year1_days, year2_days, seniority:[{years_from, extra_days}] }
   * ref  = 'YYYY-MM' | Date | undefined(=heute)   term = 'YYYY-MM-DD' | falsy
   * Rückgabe: { quota, baseDays, months, isFirstYear, isTermYear, note }
   * Verbrauch/Rest (used/remaining) bewusst NICHT hier — das rechnen die Portale
   * unterschiedlich (eigener Fall). */
  function vacationQuota(emp, cfg, ref, term) {
    var startDate = startDateOf(emp);
    if (!emp || !startDate) return { quota: 0, baseDays: 0, months: 0, isFirstYear: false, isTermYear: false, note: 'Kein Startdatum' };
    cfg = cfg || {};
    var y1 = num(cfg.year1_days, 18), y2 = num(cfg.year2_days, 20);
    var start = toDate(startDate), startYear = start.getFullYear(), startMonth = start.getMonth() + 1;
    var refDate = toDate(ref), refYear = refDate.getFullYear();
    var termD = term ? new Date(term) : null;
    var termYear = termD ? termD.getFullYear() : null;
    var termMonth = termD ? termD.getMonth() + 1 : 12;

    if (refYear < startYear) return { quota: 0, baseDays: 0, months: 0, isFirstYear: false, isTermYear: false, note: 'Vor Eintritt' };
    if (termYear != null && refYear > termYear) return { quota: 0, baseDays: 0, months: 0, isFirstYear: false, isTermYear: false, note: 'Nach Austritt' };

    var isFirstYear = (refYear === startYear);
    var isTermYear = (termYear === refYear);
    var firstMonth = isFirstYear ? (startMonth + 1) : 1;   // ab Monat NACH Eintritt
    var lastMonth = isTermYear ? termMonth : 12;            // bis einschl. Austrittsmonat
    var months = Math.max(0, lastMonth - firstMonth + 1);

    var baseDays = isFirstYear ? y1 : y2;
    if (!isFirstYear) {
      var yos = refYear - startYear;
      (cfg.seniority || []).slice().sort(function (a, b) { return b.years_from - a.years_from; })
        .some(function (s) { if (yos >= num(s.years_from, 0)) { baseDays += num(s.extra_days, 0); return true; } return false; });
    }

    var prorate = (isFirstYear || isTermYear) ? (months / 12) : 1;
    var quota = Math.round(baseDays * prorate * 2) / 2;
    var note = isFirstYear ? ('Eintrittsjahr: ' + y1 + ' Tage anteilig ' + months + '/12 = ' + quota + ' Tage')
      : (isTermYear ? ('Austrittsjahr: anteilig ' + months + '/12 = ' + quota + ' Tage')
        : ('Folgejahr: ' + baseDays + ' Tage'));
    return { quota: quota, baseDays: baseDays, months: months, isFirstYear: isFirstYear, isTermYear: isTermYear, note: note };
  }

  /* ── Urlaubsverbrauch + Konto (zwei Töpfe) — EIN Motor für beide Portale ──────
   * Ersetzt die früher divergenten Wege (hr: absDaysInYear; MA: vacation_taken_ytd
   * + Anträge, andere Tagezählung). Reine Funktionen, keine DB. */

  /* Werktage (Mo–Fr) einer Abwesenheit im Fenster [lo,hi] (inkl., 'YYYY-MM-DD').
   * Einzeltag (from===to) nutzt a.days (halbe Tage); Zeitraum zählt je Werktag 1. */
  function vacDaysInRange(a, lo, hi) {
    if (!a) return 0;
    var from = a.from; if (from == null || from === '') return 0;
    var f0 = String(from).slice(0, 10);
    var toRaw = a.to;
    var t0 = (toRaw == null || toRaw === '') ? f0 : String(toRaw).slice(0, 10);
    if (f0 === t0) {
      if (f0 < lo || f0 > hi) return 0;
      var d1 = new Date(f0 + 'T12:00:00'), w1 = d1.getDay();
      return (w1 > 0 && w1 < 6) ? num(a.days, 1) : 0;
    }
    var start = f0 < lo ? lo : f0, end = t0 > hi ? hi : t0;
    if (start > end) return 0;
    var c = 0, d = new Date(start + 'T12:00:00'), e = new Date(end + 'T12:00:00');
    while (d <= e) { var w = d.getDay(); if (w > 0 && w < 6) c++; d.setDate(d.getDate() + 1); }
    return c;
  }
  /* Werktage einer Abwesenheit im Kalenderjahr — deckt Einzeltag UND Zeitraum ab.
   * (hr.absDaysInYear delegiert hierher, damit es EINE Zählung gibt.) */
  function absDaysInYear(a, year) {
    var y = String(year);
    return vacDaysInRange(a, y + '-01-01', y + '-12-31');
  }
  /* Verbrauch = genehmigter Urlaub (type 'vacation') im Jahr, werktaggenau.
   * Zählt genommen UND genehmigt geplant (Datum entscheidet die Jahreszuordnung,
   * nicht der Eintragungszeitpunkt). absences = employee.absences[]. */
  function vacationConsumed(absences, year) {
    var y = String(year), sum = 0;
    (absences || []).forEach(function (a) { if (a && a.type === 'vacation') sum += vacDaysInRange(a, y + '-01-01', y + '-12-31'); });
    return Math.round(sum * 2) / 2;
  }
  /* Verfallsdatum des Resturlaubs (Topf A): MA-Override (volles Datum) sonst
   * systemweit MM-DD (cfg.carry_expire, Default '06-30') im jeweiligen Jahr. */
  function carryExpiryDate(year, cfg, accountRow) {
    if (accountRow && accountRow.carry_expires_on) return String(accountRow.carry_expires_on).slice(0, 10);
    var md = (cfg && cfg.carry_expire) || '06-30';
    return String(year) + '-' + md;
  }
  /* Zwei-Töpfe-Konto. Verbraucht wird ZUERST Topf A (Resturlaub Vorjahr), aber nur
   * durch Urlaub mit Datum ≤ Verfall; danach Topf B (Anspruch). Verfallener Rest
   * wird SICHTBAR ausgewiesen (carryExpired), nicht auf null gerechnet.
   * opts = { year, quota, carryIn, expiry:'YYYY-MM-DD', today:'YYYY-MM-DD', absences } */
  function vacationAccount(opts) {
    opts = opts || {};
    var year = opts.year, quota = num(opts.quota, 0), carryIn = num(opts.carryIn, 0);
    var expiry = opts.expiry, today = opts.today, abs = opts.absences || [];
    var yStart = String(year) + '-01-01', yEnd = String(year) + '-12-31';
    var r = function (x) { return Math.round(x * 2) / 2; };
    var sumRange = function (lo, hi) { var s = 0; abs.forEach(function (a) { if (a && a.type === 'vacation') s += vacDaysInRange(a, lo, hi); }); return s; };
    var consumed = r(sumRange(yStart, yEnd));
    var byExpiry = r(sumRange(yStart, expiry));           // Urlaub mit Datum ≤ Verfall (zieht Topf A)
    var afterExpiry = r(consumed - byExpiry);
    var taken = r(sumRange(yStart, today));               // genommen (bis heute)
    var planned = r(consumed - taken);                    // genehmigt geplant (nach heute)
    var carryUsed = Math.min(byExpiry, carryIn);
    var quotaUsed = r((byExpiry - carryUsed) + afterExpiry);
    var expiryPassed = today > expiry;
    var carryAvail = expiryPassed ? 0 : r(carryIn - carryUsed);
    var carryExpired = expiryPassed ? r(carryIn - carryUsed) : 0;
    var quotaAvail = r(quota - quotaUsed);
    var available = r(carryAvail + Math.max(0, quotaAvail));
    var overused = quotaAvail < 0 ? r(-quotaAvail) : 0;
    return {
      year: year, quota: quota, carryIn: carryIn, total: r(quota + carryIn), expiry: expiry, expiryPassed: expiryPassed,
      consumed: consumed, taken: taken, planned: planned,
      carryUsed: r(carryUsed), quotaUsed: quotaUsed, carryAvail: carryAvail, carryExpired: carryExpired,
      quotaAvail: Math.max(0, quotaAvail), available: available, overused: overused
    };
  }

  /* Feiertage → flache Liste der Datums-Strings. cfg = { <gruppe>: [{date, ...}] } */
  function holidayDates(cfg) {
    try {
      if (cfg && typeof cfg === 'object') {
        return Object.keys(cfg).reduce(function (a, k) { return a.concat(cfg[k] || []); }, [])
          .map(function (h) { return h && h.date; }).filter(Boolean);
      }
    } catch (e) {}
    return [];
  }

  global.JSRCalc = {
    vacationQuota: vacationQuota, holidayDates: holidayDates,
    vacDaysInRange: vacDaysInRange, absDaysInYear: absDaysInYear,
    vacationConsumed: vacationConsumed, carryExpiryDate: carryExpiryDate, vacationAccount: vacationAccount
  };
})(typeof window !== 'undefined' ? window : this);
