/* Langzeit-Kapazitätsmodell — EINE Wahrheit für Leitstand und Präsentation.
 *
 * Grundlage ist die Datei des Auftraggebers „Long Term Capacity 25H Sales_Support.xlsx":
 * je Blatt (Sales/Support) 25 beschriftete Zeilen mal 12 Monatsspalten, in drei Blöcken.
 *
 * Drei Arten von Zeilen:
 *   'file'  kommt unverändert aus dem Upload.
 *   'edit'  im System anpassbar. Das sind genau die vier im Original rot markierten Zeilen
 *           (Forecast, Attrition, New Hire FTE, Training Attrition FTE). Rot sind sie dort nur
 *           auf dem Blatt Support; es sind aber dieselben Zeilen, die sich auch bei Sales ändern,
 *           deshalb sind sie hier bei beiden Skills offen (Entscheidung 2026-09-29).
 *   'calc'  wird hier gerechnet und NIE aus der Datei übernommen. Sonst passt das Ergebnis nach
 *           einer Änderung am Forecast nicht mehr zu den Vorgaben.
 *
 * Die Datei rechnet dieselbe Sache auf beiden Blättern unterschiedlich: Productivity % ist bei
 * Sales eine Formel und bei Support eingetippt, Shrinkage und New Hire after attrition umgekehrt.
 * Hier gilt für beide Skills dieselbe Regel: Productivity nach der Sales-Formel, Shrinkage und
 * New Hire after attrition nach der Support-Formel.
 *
 * Genutzt von frontend/hr.html (Cockpit, Datenimport-Editor, Berichts-Store) und mittelbar von
 * der Folie „Langzeit-Entwicklung" (shared/presentation-slides.js), die das fertige Modell aus
 * dem Bericht rendert.
 */
(function (global) {
  'use strict';

  var BLOCKS = [
    { key: 'bedarf',   title: 'Bedarf und Arbeitszeit' },
    { key: 'personal', title: 'Personalbewegung' },
    { key: 'ergebnis', title: 'Ergebnis' }
  ];

  // Reihenfolge = Reihenfolge in der Datei (Zeile 3 bis 29). ind:1 = eingerückte Unterzeile.
  var ROWS = [
    { key: 'forecast',     block: 'bedarf',   kind: 'edit', fmt: 'h',   label: 'Forecast (Hours)' },
    { key: 'workdays',     block: 'bedarf',   kind: 'file', fmt: 'i',   label: 'Work Days' },
    { key: 'gross',        block: 'bedarf',   kind: 'file', fmt: 'i',   label: 'Working Gross Time (Min.)', ind: 1 },
    { key: 'breaks',       block: 'bedarf',   kind: 'file', fmt: 'i',   label: 'Short Breaks (Min.)', ind: 1 },
    { key: 'meal',         block: 'bedarf',   kind: 'file', fmt: 'i',   label: 'Meal (Min.)', ind: 1 },
    { key: 'net',          block: 'bedarf',   kind: 'file', fmt: 'n',   label: 'Working Net Time (Hours)' },
    { key: 'productivity', block: 'bedarf',   kind: 'calc', fmt: 'pct', label: 'Productivity %' },
    { key: 'breakmeal',    block: 'bedarf',   kind: 'file', fmt: 'pct', label: 'Break and Meal %', ind: 1 },
    { key: 'inoffice',     block: 'bedarf',   kind: 'file', fmt: 'pct', label: 'In Office Shrinkage % (Unpaid Aux)', ind: 1 },
    { key: 'shrinkage',    block: 'bedarf',   kind: 'calc', fmt: 'pct', label: 'Shrinkage' },
    { key: 'plannedout',   block: 'bedarf',   kind: 'file', fmt: 'pct', label: 'Planned Out Office Shrinkage % (Vacations etc.)', ind: 1 },
    { key: 'unplannedout', block: 'bedarf',   kind: 'file', fmt: 'pct', label: 'Unplanned Out Office Shrinkage % (Technical Issue, Health Issues etc.)', ind: 1 },
    { key: 'vacdays',      block: 'bedarf',   kind: 'file', fmt: 'n',   label: 'Vacations Days' },
    { key: 'vacsanity',    block: 'bedarf',   kind: 'file', fmt: 'n',   label: 'Vacations sanity check' },
    { key: 'attrition',    block: 'personal', kind: 'edit', fmt: 'n',   label: 'Attrition (by the end of the month)' },
    { key: 'newhire',      block: 'personal', kind: 'edit', fmt: 'n',   label: 'New Hire FTE', ind: 1 },
    { key: 'trainattr',    block: 'personal', kind: 'edit', fmt: 'n',   label: 'Training Attrition FTE', ind: 1 },
    { key: 'newhireafter', block: 'personal', kind: 'calc', fmt: 'n',   label: 'New Hire after attrition' },
    { key: 'eomfte',       block: 'ergebnis', kind: 'file', fmt: 'n',   label: 'EOM Forecasted FTE (Productive)' },
    { key: 'neededfte',    block: 'ergebnis', kind: 'calc', fmt: 'n',   label: 'Needed FTE' },
    { key: 'overtime',     block: 'ergebnis', kind: 'file', fmt: 'i',   label: 'Overtime' },
    { key: 'productiveh',  block: 'ergebnis', kind: 'calc', fmt: 'h',   label: 'Productive (Hours)' },
    { key: 'coverage',     block: 'ergebnis', kind: 'calc', fmt: 'pct', label: 'Coverage %' },
    { key: 'overunder',    block: 'ergebnis', kind: 'calc', fmt: 'n',   label: 'Over/Under FTE' },
    { key: 'netdiff',      block: 'ergebnis', kind: 'calc', fmt: 'h',   label: 'Net Difference in hours' }
  ];

  var EDIT_KEYS = ROWS.filter(function (r) { return r.kind === 'edit'; }).map(function (r) { return r.key; });

  function norm(s) { return String(s == null ? '' : s).toLowerCase().replace(/[^a-z0-9]/g, ''); }

  // Beschriftung der Datei -> Schlüssel. Reihenfolge zählt: das Längere/Spezifischere zuerst,
  // sonst schluckt „planned out office" auch „unplanned out office".
  var MATCH = [
    ['unplannedout', function (n) { return n.indexOf('unplannedoutoffice') >= 0; }],
    ['plannedout',   function (n) { return n.indexOf('plannedoutoffice') >= 0; }],
    ['inoffice',     function (n) { return n.indexOf('inofficeshrinkage') >= 0; }],
    ['breakmeal',    function (n) { return n.indexOf('breakandmeal') >= 0; }],
    ['shrinkage',    function (n) { return n === 'shrinkage'; }],
    ['productivity', function (n) { return n.indexOf('productivity') >= 0; }],
    ['forecast',     function (n) { return n.indexOf('forecast') >= 0 && n.indexOf('hour') >= 0; }],
    ['workdays',     function (n) { return n.indexOf('workdays') >= 0 || n.indexOf('workingdays') >= 0; }],
    ['gross',        function (n) { return n.indexOf('workinggross') >= 0; }],
    ['breaks',       function (n) { return n.indexOf('shortbreak') >= 0; }],
    ['meal',         function (n) { return n.indexOf('meal') === 0; }],
    ['net',          function (n) { return n.indexOf('workingnet') >= 0; }],
    ['vacsanity',    function (n) { return n.indexOf('sanity') >= 0; }],
    ['vacdays',      function (n) { return n.indexOf('vacationsday') >= 0 || n.indexOf('vacationday') >= 0; }],
    ['newhireafter', function (n) { return n.indexOf('newhireafter') >= 0; }],
    ['newhire',      function (n) { return n.indexOf('newhirefte') >= 0; }],
    ['trainattr',    function (n) { return n.indexOf('trainingattrition') >= 0; }],
    ['attrition',    function (n) { return n.indexOf('attrition') >= 0; }],
    ['eomfte',       function (n) { return n.indexOf('eomforecast') >= 0; }],
    ['neededfte',    function (n) { return n.indexOf('neededfte') >= 0; }],
    ['overtime',     function (n) { return n.indexOf('overtime') >= 0; }],
    ['productiveh',  function (n) { return n.indexOf('productivehour') >= 0; }],
    ['coverage',     function (n) { return n.indexOf('coverage') >= 0; }],
    ['overunder',    function (n) { return n.indexOf('overunder') >= 0; }],
    ['netdiff',      function (n) { return n.indexOf('netdifference') >= 0; }]
  ];

  function keyOf(label) {
    var n = norm(label); if (!n) return null;
    for (var i = 0; i < MATCH.length; i++) { if (MATCH[i][1](n)) return MATCH[i][0]; }
    return null;
  }

  // Zahl aus der Datei oder aus einem Eingabefeld. Leer bleibt leer (null), damit „kein Wert"
  // nicht als 0 durchrutscht — genau der Fehler, der uns bei den Stunden schon einmal getroffen hat.
  function num(v) {
    if (v == null) return null;
    if (typeof v === 'number') return isFinite(v) ? v : null;
    var s = String(v).trim(); if (s === '') return null;
    s = s.replace(/[\s ']/g, '').replace(/%$/, '');
    if (/,\d{1,3}$/.test(s) && s.indexOf('.') < 0) s = s.replace(',', '.');
    else s = s.replace(/,/g, '');
    var n = Number(s); return isFinite(n) ? n : null;
  }

  function fmt(v, f) {
    if (v == null || !isFinite(v)) return '·';
    if (f === 'pct') return de(v * 100, 1) + ' %';
    if (f === 'i')   return de(Math.round(v), 0);
    if (f === 'h')   return de(v, 1);
    var r = Math.round(v * 10) / 10;                       // 'n': bis eine Nachkommastelle
    return de(r, (Math.abs(r * 10 % 10) < 0.001) ? 0 : 1);
  }
  function de(v, d) {
    var s = (Math.round(v * Math.pow(10, d)) / Math.pow(10, d)).toFixed(d);
    var p = s.split('.'); p[0] = p[0].replace(/\B(?=(\d{3})+(?!\d))/g, '.');
    return p.join(',');
  }

  function empty12() { return [null, null, null, null, null, null, null, null, null, null, null, null]; }

  /* rec = { rows:[{label,m:[12]}], overrides:{key:[12]}, start_month, start_year }
   * Ergebnis: { startMonth, startYear, months:[{m,y,cur}], blocks:[{key,title,rows:[…]}],
   *             rows:[flach], extra:[unbekannte Zeilen der Datei], hasEdits }
   * Jede Zeile: { key,label,ind,kind,fmt,m:[12 Zahlen|null], raw:[12 Werte aus der Datei], edited:[12 bool] } */
  function build(rec) {
    rec = rec || {};
    var src = {}, extra = [];
    (rec.rows || []).forEach(function (r) {
      var k = keyOf(r && r.label);
      var vals = (r && r.m) || [];
      var m = empty12(); for (var i = 0; i < 12; i++) m[i] = num(vals[i]);
      if (k && !src[k]) src[k] = m;
      else if (!k) extra.push({ key: null, label: String((r && r.label) || ''), ind: 0, kind: 'file', fmt: 'n', m: m, edited: [] });
    });

    var ov = rec.overrides || {};
    var val = {}, edited = {}, hasEdits = false;
    ROWS.forEach(function (d) {
      var base = src[d.key] || empty12();
      var o = ov[d.key];
      var m = base.slice(), ed = [false, false, false, false, false, false, false, false, false, false, false, false];
      if (d.kind === 'edit' && o) {
        for (var i = 0; i < 12; i++) {
          var x = num(o[i]);
          if (x != null) { if (x !== base[i]) { ed[i] = true; hasEdits = true; } m[i] = x; }
        }
      }
      val[d.key] = m; edited[d.key] = ed;
    });

    // Gerechnete Zeilen, Monat für Monat. Fehlt eine Zutat, bleibt das Ergebnis leer.
    var f = function (k, i) { return val[k][i]; };
    for (var i = 0; i < 12; i++) {
      var breakmeal = f('breakmeal', i), inoffice = f('inoffice', i);
      var prod = (breakmeal == null && inoffice == null) ? null : (1 - ((breakmeal || 0) + (inoffice || 0)));
      val.productivity[i] = prod;

      var pl = f('plannedout', i), un = f('unplannedout', i);
      var shr = (pl == null && un == null) ? null : ((pl || 0) + (un || 0));
      val.shrinkage[i] = shr;

      var nh = f('newhire', i), ta = f('trainattr', i);
      val.newhireafter[i] = (nh == null && ta == null) ? null : ((nh || 0) - (ta || 0));

      var fc = f('forecast', i), wd = f('workdays', i), gr = f('gross', i), eom = f('eomfte', i), ot = f('overtime', i);
      // Stunden je FTE und Monat: Arbeitstage x Bruttozeit x Produktivität x (1 - Shrinkage).
      // Genau die Formel der Datei, die dort ebenfalls auf der Brutto- und nicht der Nettozeit steht.
      var perFte = (wd == null || gr == null || prod == null || shr == null) ? null : (wd * (gr / 60) * prod * (1 - shr));

      val.neededfte[i]   = (fc == null || !perFte) ? null : (fc / perFte);
      val.productiveh[i] = (perFte == null || eom == null) ? null : (perFte * eom + (ot || 0));
      val.coverage[i]    = (val.productiveh[i] == null || !fc) ? null : (val.productiveh[i] / fc);
      val.overunder[i]   = (eom == null || val.neededfte[i] == null) ? null : (eom - val.neededfte[i]);
      val.netdiff[i]     = (val.productiveh[i] == null || fc == null) ? null : (val.productiveh[i] - fc);
    }

    var flat = ROWS.map(function (d) {
      return { key: d.key, label: d.label, ind: d.ind || 0, kind: d.kind, fmt: d.fmt,
               m: val[d.key].slice(), raw: (src[d.key] || empty12()).slice(), edited: edited[d.key].slice() };
    });
    var byKey = {}; flat.forEach(function (r) { byKey[r.key] = r; });

    var sm = Math.max(1, Math.min(12, Number(rec.start_month || rec.startMonth || 1))) - 1;
    var yr = Number(rec.start_year || rec.startYear) || new Date().getFullYear();
    var now = new Date(), nowY = now.getFullYear(), nowM = now.getMonth() + 1;
    var months = []; for (var mi = 0; mi < 12; mi++) {
      var mm = (sm + mi) % 12, yy = yr + Math.floor((sm + mi) / 12);
      months.push({ m: mm, y: yy, cur: (yy === nowY && mm + 1 === nowM) });
    }

    var blocks = BLOCKS.map(function (b) {
      return { key: b.key, title: b.title, rows: ROWS.filter(function (d) { return d.block === b.key; }).map(function (d) { return byKey[d.key]; }) };
    });
    if (extra.length) blocks.push({ key: 'extra', title: 'Weitere Zeilen aus der Datei', rows: extra });

    return { startMonth: sm + 1, startYear: yr, months: months, blocks: blocks, rows: flat, byKey: byKey, extra: extra, hasEdits: hasEdits };
  }

  // Monatsnamen, an einer Stelle.
  var MONTHS = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];

  global.Longterm = { BLOCKS: BLOCKS, ROWS: ROWS, EDIT_KEYS: EDIT_KEYS, MONTHS: MONTHS,
                      keyOf: keyOf, num: num, fmt: fmt, build: build };
})(typeof window !== 'undefined' ? window : this);
