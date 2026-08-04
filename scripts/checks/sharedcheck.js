#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════════
// sharedcheck.js — Prüfkette für frontend/shared/jsr-calc.js (im Deploy).
//   1. Datei parst/läuft (Syntaxfehler blocken den Deploy).
//   2. window.JSRCalc + erwartete Funktionen existieren.
//   3. Die Urlaubsformel liefert die bekannten Beispielwerte (Regel eingefroren).
// Damit ist die geteilte Datei NICHT außerhalb der Prüfkette.
// ════════════════════════════════════════════════════════════════════════════
const fs = require('fs');
const vm = require('vm');
const path = require('path');

const FILE = path.join(__dirname, '..', '..', 'frontend', 'shared', 'jsr-calc.js');

function fail(msg) { console.error('✗ sharedcheck: ' + msg); process.exit(1); }

let src;
try { src = fs.readFileSync(FILE, 'utf8'); } catch (e) { fail('jsr-calc.js nicht lesbar: ' + e.message); }

const sandbox = { window: {}, console: console };
vm.createContext(sandbox);
try { vm.runInContext(src, sandbox, { filename: 'jsr-calc.js' }); }
catch (e) { fail('Syntax-/Laufzeitfehler beim Laden: ' + e.message); }

const JSR = sandbox.window.JSRCalc;
if (!JSR) fail('window.JSRCalc nicht gesetzt.');
if (typeof JSR.vacationQuota !== 'function') fail('JSRCalc.vacationQuota fehlt.');
if (typeof JSR.holidayDates !== 'function') fail('JSRCalc.holidayDates fehlt.');

// Urlaubsformel gegen die abgestimmten Beispiele (Kalenderjahr 2026, Standard-Config).
const cfg = { year1_days: 18, year2_days: 20, seniority: [] };
const cases = [
  ['2025-11-04', 20], ['2025-02-18', 20], ['2026-02-16', 15],
  ['2026-03-01', 13.5], ['2026-07-20', 7.5], ['2026-12-15', 0],
];
let bad = 0;
for (const [d, exp] of cases) {
  const got = JSR.vacationQuota({ contract: { start: d } }, cfg, '2026-06', '').quota;
  if (got !== exp) { console.error('  Urlaubsformel falsch: Eintritt ' + d + ' → ' + got + ' (erwartet ' + exp + ')'); bad++; }
}
if (bad) fail(bad + ' Urlaubs-Beispiel(e) weichen ab — Regel gebrochen.');

// holidayDates: flacher Datums-Array aus gruppierter Config.
const hd = JSR.holidayDates({ 2026: [{ date: '2026-01-01' }, { date: '2026-12-25' }] });
if (!(Array.isArray(hd) && hd.length === 2 && hd[0] === '2026-01-01')) fail('holidayDates liefert nicht die erwartete flache Liste.');

// Urlaubskonto (zwei Töpfe). Neue Funktionen vorhanden?
['vacDaysInRange', 'absDaysInYear', 'vacationConsumed', 'carryExpiryDate', 'vacationAccount'].forEach(function (fn) {
  if (typeof JSR[fn] !== 'function') fail('JSRCalc.' + fn + ' fehlt.');
});
// Einzeltag-Werktage (a.days respektiert), Jahres-/Fenster-Zählung.
const vd = (from, to, days) => ({ type: 'vacation', from: from, to: to || from, days: days });
function expectAcc(label, opts, exp) {
  const a = JSR.vacationAccount(opts);
  Object.keys(exp).forEach(function (k) {
    if (a[k] !== exp[k]) { console.error('  Konto ' + label + ': ' + k + ' = ' + a[k] + ' (erwartet ' + exp[k] + ')'); accBad++; }
  });
}
let accBad = 0;
// A) Verfall vorbei (today>expiry): Resturlaub zuerst, Rest verfällt sichtbar.
const absA = [vd('2026-02-03'), vd('2026-02-04'), vd('2026-02-05'), vd('2026-07-14'), vd('2026-07-15')];
expectAcc('A', { year: 2026, quota: 20, carryIn: 5, expiry: '2026-06-30', today: '2026-08-01', absences: absA },
  { consumed: 5, taken: 5, planned: 0, carryUsed: 3, carryExpired: 2, quotaUsed: 2, quotaAvail: 18, carryAvail: 0, available: 18 });
// B) Vor Verfall, geplanter Urlaub im Resturlaub-Fenster zieht Topf A.
const absB = [vd('2026-02-03'), vd('2026-02-04'), vd('2026-02-05'), vd('2026-06-16'), vd('2026-06-17')];
expectAcc('B', { year: 2026, quota: 20, carryIn: 5, expiry: '2026-06-30', today: '2026-05-01', absences: absB },
  { consumed: 5, taken: 3, planned: 2, carryUsed: 5, carryAvail: 0, quotaUsed: 0, quotaAvail: 20, available: 20, carryExpired: 0 });
// C) Resturlaub nur teils verbraucht, vor Verfall → Rest bleibt verfügbar.
const absC = [vd('2026-02-03'), vd('2026-02-04'), vd('2026-02-05')];
expectAcc('C', { year: 2026, quota: 20, carryIn: 8, expiry: '2026-06-30', today: '2026-05-01', absences: absC },
  { consumed: 3, carryUsed: 3, carryAvail: 5, quotaUsed: 0, quotaAvail: 20, available: 25, total: 28, carryExpired: 0 });
if (accBad) fail(accBad + ' Konto-Erwartung(en) weichen ab — Kontomodell gebrochen.');

console.log('sharedcheck: JSRCalc geladen, Urlaubsformel 6/6 korrekt, Konto 3/3 korrekt, holidayDates ok. PASS');
