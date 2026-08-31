#!/usr/bin/env node
/* menucheck.js — Deploy-Vorabpruefung: jeder Menuepunkt (navSections in hr.html) muss im Katalog
 * MENU_BADGE_MAIN_ITEMS stehen, sonst ist er in der HR-Tab-Sperren-Matrix (HR_LOCKABLE_TABS/
 * HR_PROTECTED_ITEMS leiten daraus ab) NICHT freigeb-/sperrbar. Genau wie iconcheck/statuscheck:
 * zwei Listen, die dieselbe Wahrheit doppelt halten, beim Deploy gegeneinander pruefen.
 *
 * Zwei erlaubte Ausnahmen (bewusst NICHT in MENU_BADGE_MAIN_ITEMS):
 *   - activity_log: always-Tab mit eigenem Rollenfilter in der Nav, hat bewusst keine Matrix-Spalte.
 *   - hrtablocks:   wird in HR_LOCKABLE_TABS separat angehaengt (Zeile mit {key:'hrtablocks'}).
 */
const fs = require('fs');
const path = require('path');

const HR = process.argv[2] || path.join(__dirname, '..', '..', 'frontend', 'hr.html');
const src = fs.readFileSync(HR, 'utf8');

// Balancierten Array-Block ab `const <NAME> = [` bis zum passenden `]` schneiden.
function sliceArray(name){
  const anchor = 'const ' + name + ' = [';
  let i = src.indexOf(anchor);
  if (i < 0){ i = src.indexOf('const ' + name + '=['); if (i < 0) return null; i += ('const '+name+'=[').length - 1; }
  else i += anchor.length - 1;   // auf das '[' zeigen
  let depth = 0;
  for (let k = i; k < src.length; k++){
    const c = src[k];
    if (c === '[') depth++;
    else if (c === ']'){ depth--; if (depth === 0) return src.slice(i, k + 1); }
  }
  return null;
}
function keysOf(block){
  if (!block) return [];
  const out = [];
  const re = /key:\s*'([a-z0-9_]+)'/gi;
  let m; while ((m = re.exec(block))) out.push(m[1]);
  return out;
}

// navSections wurde in die reine Top-Level-Funktion buildNavSections() ausgelagert (EINE Quelle fuer die
// Live-Sidebar UND die „Wer sieht was"-Uebersicht). Der Katalog-Abgleich schneidet jetzt deren return-Array.
function sliceBuildNav(){
  const a = src.indexOf('function buildNavSections');
  if (a < 0) return null;
  const r = src.indexOf('return [', a);
  if (r < 0) return null;
  const i = r + 'return '.length;   // auf '[' zeigen
  let depth = 0;
  for (let k = i; k < src.length; k++){
    const c = src[k];
    if (c === '[') depth++;
    else if (c === ']'){ depth--; if (depth === 0) return src.slice(i, k + 1); }
  }
  return null;
}
const navBlock = sliceBuildNav();
const catBlock = sliceArray('MENU_BADGE_MAIN_ITEMS');
if (!navBlock || !catBlock){
  console.error('menucheck: konnte navSections oder MENU_BADGE_MAIN_ITEMS nicht finden — Ankertext geaendert?');
  process.exit(1);
}

const menuKeys = Array.from(new Set(keysOf(navBlock)));
const catalog  = new Set(keysOf(catBlock));
const ALLOW = new Set(['activity_log', 'akquise_leads', 'akquise_einspeisen', 'akquise_vorlagen']);   // ohne Katalog-Eintrag: activity_log (eigener Rollenfilter); Akquise-Sektion (Sales-Freigabeliste, nicht über die Tab-Matrix sperrbar)

const missing = menuKeys.filter(k => !catalog.has(k) && !ALLOW.has(k));
// Zusatzhinweis (kein Blocker): Katalog-Keys, die es im Menue nicht (mehr) gibt.
const menuSet = new Set(menuKeys);
const stale = Array.from(catalog).filter(k => !menuSet.has(k) && !ALLOW.has(k));

if (stale.length){
  console.log('Hinweis: im Katalog MENU_BADGE_MAIN_ITEMS, aber nicht im Menue (unkritisch, evtl. Altlast): ' + stale.join(', '));
}
if (missing.length){
  console.error('✗ Menuepunkte OHNE Katalog-Eintrag — in der HR-Tab-Sperren-Matrix nicht freigeb-/sperrbar:');
  console.error('    ' + missing.join(', '));
  console.error('  Fix: diese Keys in MENU_BADGE_MAIN_ITEMS (hr.html) mit {key,label} ergaenzen.');
  console.error('  (Oder, falls bewusst nie sperrbar: in menucheck.js ALLOW aufnehmen mit Begruendung.)');
  process.exit(1);
}
console.log('RESULT: PASS (' + menuKeys.length + ' Menuepunkte alle im Katalog abgedeckt)');
process.exit(0);
