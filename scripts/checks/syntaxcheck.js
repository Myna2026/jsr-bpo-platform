#!/usr/bin/env node
// syntaxcheck.js — ECHTER Parse-Check fuer ALLE Inline-Skripte in frontend/hr.html.
//
// Ersetzt den alten Klammerzaehler (balcheck): ein echter Parser fangt unbalancierte
// Klammern zuverlaessig und OHNE Fehlalarme (kein Mitzaehlen in Kommentaren/Strings).
// Geprueft werden:
//   • jeder <script type="text/babel">-Block  → @babel/parser mit JSX
//   • jedes Nicht-Babel-Inline-Skript (Config/Seed) → @babel/parser als reines JS
//   • Struktur: Anzahl <script> == Anzahl </script>
// Externe Skripte (src=…, kein Body) werden uebersprungen.
//
// Exit 0 = alles parst sauber + Tag-Balance ok. Exit 1 = Parse-Fehler / Imbalance / Parser fehlt.

const fs = require("fs"), cp = require("child_process"), path = require("path");

let root = "."; try { root = cp.execSync("git rev-parse --show-toplevel").toString().trim(); } catch (e) {}
const here = __dirname;

// Parser laden — bei Bedarf einmalig lokal nachinstallieren (self-healing, kein stiller Skip).
let parser;
function loadParser() { try { parser = require(path.join(here, "node_modules/@babel/parser")); return true; } catch (e) { return false; } }
if (!loadParser()) {
  process.stderr.write("  @babel/parser fehlt — installiere einmalig (npm install aus scripts/checks/package.json)…\n");
  try { cp.execSync("npm install", { cwd: here, stdio: "ignore" }); } catch (e) {}
  if (!loadParser()) {
    console.log("RESULT: FAIL  (@babel/parser nicht verfuegbar — 'cd scripts/checks && npm install')");
    process.exit(1);
  }
}

const file = process.argv[2] || path.join(root, "frontend/hr.html");
const s = fs.readFileSync(file, "utf8");

// Zeile (1-basiert) an einem Zeichen-Offset.
const lineAt = (idx) => s.slice(0, idx).split("\n").length;

const openRe = /<script\b([^>]*)>/g;
let babelBlocks = 0, otherBlocks = 0, failed = 0, m;
while ((m = openRe.exec(s))) {
  const attrs = m[1] || "";
  if (/\bsrc\s*=/.test(attrs)) continue;                          // externes Skript, kein Inline-Body
  const type = (attrs.match(/type\s*=\s*["']([^"']+)["']/) || [])[1] || "";
  if (type && !/text\/(babel|javascript)/.test(type)) continue;   // z.B. application/json → kein JS
  const end = s.indexOf("</script>", m.index);
  if (end === -1) continue;
  const bodyStart = m.index + m[0].length;
  const body = s.slice(bodyStart, end);
  const baseLine = lineAt(bodyStart);
  const isBabel = /text\/babel/.test(type);
  if (isBabel) babelBlocks++; else otherBlocks++;
  const plugins = isBabel
    ? ["jsx", "optionalChaining", "nullishCoalescingOperator", "objectRestSpread"]
    : ["optionalChaining", "nullishCoalescingOperator", "objectRestSpread"];
  try {
    parser.parse(body, { sourceType: "unambiguous", errorRecovery: false, plugins });
  } catch (err) {
    failed++;
    const loc = err.loc || {};
    const fileLine = loc.line ? baseLine + loc.line - 1 : "?";
    console.log(`  ✗ ${isBabel ? "Babel" : "JS"}-Block #${babelBlocks + otherBlocks}: ${err.message.replace(/\s*\(\d+:\d+\)\s*$/, "")}`);
    console.log(`    -> ${path.relative(root, file)}:${fileLine}:${(loc.column ?? 0) + 1}`);
  }
}

// Struktur: jedes geoeffnete <script> muss ein </script> haben.
const openTags = (s.match(/<script\b/g) || []).length;
const closeTags = (s.match(/<\/script>/g) || []).length;
const tagsOk = openTags === closeTags;

const ok = failed === 0 && tagsOk;
console.log(`geparst: ${babelBlocks} Babel + ${otherBlocks} JS-Inline   fehlerhaft: ${failed}   ${failed === 0 ? "ok" : "SYNTAXFEHLER"}`);
console.log(`script-Tags: ${openTags}/${closeTags}   ${tagsOk ? "ok" : "IMBALANCE"}`);
console.log("RESULT:", ok ? "PASS" : "FAIL");
process.exit(ok ? 0 : 1);
