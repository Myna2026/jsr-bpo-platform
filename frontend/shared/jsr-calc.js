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

  global.JSRCalc = { vacationQuota: vacationQuota, holidayDates: holidayDates };
})(typeof window !== 'undefined' ? window : this);
