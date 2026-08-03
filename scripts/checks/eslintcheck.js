#!/usr/bin/env node
// eslintcheck.js — ECHTER Scope-Check fuer frontend/hr.html.
//
// Faengt die Klasse "verwaiste Referenz": eine Variable/Funktion wird geloescht
// (z.B. bei einem Aufraeum-Block), Referenzen darauf bleiben stehen. Solche
// freien Bezeichner sind ein Laufzeit-ReferenceError, aber KEIN Syntaxfehler —
// jsxcheck/syntaxcheck sehen sie nicht.
//
// Trick: die 20 <script type="text/babel">-Bloecke teilen sich zur Laufzeit EINE
// globale Scope (eine in Block 3 definierte Funktion wird in Block 11 genutzt).
// Darum werden sie hier zu EINER virtuellen Datei zusammengefuegt und als Ganzes
// gelintet — genau das modelliert die Laufzeit. Cross-Block-Referenzen loesen
// dadurch korrekt auf (keine Falschmeldungen), weil es zur Laufzeit 0 Namens-
// kollisionen gibt (sonst wuerde die App gar nicht laden).
//
// Regeln:
//   no-undef       : error  -> blockt den Deploy (die verwaiste-Referenz-Klasse)
//   no-unused-vars : warn   -> sichtbar, blockt NICHT (sonst waere der Alt-Sockel
//                              ein Dauerblocker). Bewusst gehaltene Symbole per
//                              "// eslint-disable-next-line no-unused-vars" markieren.
//
// GRENZE (ehrlich): faengt freie, undeklarierte BEZEICHNER. Einen vertippten
// PROPERTY-Zugriff (obj.Tpyo) faengt es NICHT — dafuer braeuchte es ein Typsystem.
//
// Exit 0 = keine no-undef-Fehler. Exit 1 = no-undef-Fehler ODER Tooling fehlt.

const fs = require("fs"), cp = require("child_process"), path = require("path");

let root = "."; try { root = cp.execSync("git rev-parse --show-toplevel").toString().trim(); } catch (e) {}
const here = __dirname;

// --- Tooling laden, bei Bedarf einmalig lokal nachinstallieren (self-healing, kein stiller Skip) ---
const DEPS = ["eslint", "eslint-plugin-react", "globals"];
function loadDeps() {
  try {
    return {
      Linter: require(path.join(here, "node_modules/eslint")).Linter,
      react: require(path.join(here, "node_modules/eslint-plugin-react")),
      globals: require(path.join(here, "node_modules/globals")),
    };
  } catch (e) { return null; }
}
let tools = loadDeps();
if (!tools) {
  process.stderr.write("  eslint/eslint-plugin-react/globals fehlen — installiere einmalig (npm install aus scripts/checks/package.json)…\n");
  // npm install (ohne Paketnamen) liest die package.json und installiert ALLE deklarierten
  // Dev-Tools gemeinsam — pruned die anderen Checks (@babel/parser) NICHT weg.
  try { cp.execSync("npm install", { cwd: here, stdio: "ignore" }); } catch (e) {}
  tools = loadDeps();
  if (!tools) {
    console.log("RESULT: FAIL  (eslint-Tooling nicht verfuegbar — 'cd scripts/checks && npm install " + DEPS.join(" ") + "')");
    process.exit(1);
  }
}
const { Linter, react, globals } = tools;

const file = process.argv[2] || path.join(root, "frontend/hr.html");
const s = fs.readFileSync(file, "utf8");

// --- Alle INLINE-JS-Scripts zu einer virtuellen Datei fuegen, Zeilen-Map fuehren ---
// Wichtig: nicht nur text/babel. Zur Laufzeit teilen sich AUCH plain <script>-Bloecke
// (z.B. der "Abmahnung PDF Generator") dieselbe globale Scope. Wer die weglaesst,
// bekommt Falsch-Positive (no-undef auf real globale Funktionen). Externe (src=) und
// Nicht-JS-Typen (application/json o.ae.) werden uebersprungen.
// blocks[i] = { virtualStart, fileStart, lines }  (jeweils 1-basierte Zeile des Body-Anfangs)
const openRe = /<script([^>]*)>/g;
function isInlineJs(attrs) {
  if (/\bsrc=/.test(attrs)) return false;                       // extern
  const t = attrs.match(/type=["']([^"']+)["']/);
  if (!t) return true;                                          // kein type = klassisches JS
  return /^(text\/babel|text\/javascript|application\/javascript|module)$/i.test(t[1]);
}
let virtual = "", m;
const blocks = [];
while ((m = openRe.exec(s))) {
  if (!isInlineJs(m[1])) continue;
  const end = s.indexOf("</script>", m.index);
  if (end === -1) continue;
  const bodyStart = m.index + m[0].length;
  const body = s.slice(bodyStart, end);
  const fileStart = s.slice(0, bodyStart).split("\n").length; // Datei-Zeile des ersten Body-Zeichens
  if (virtual && !virtual.endsWith("\n")) virtual += "\n";
  const virtualStart = virtual.split("\n").length;           // virtuelle Zeile des ersten Body-Zeichens
  virtual += body;
  if (!virtual.endsWith("\n")) virtual += "\n";
  virtual += ";\n"; // Trenn-Statement zwischen Bloecken
  blocks.push({ virtualStart, fileStart, lines: body.split("\n").length });
}

// virtuelle Zeile -> hr.html-Zeile
function toFileLine(v) {
  for (const b of blocks) {
    if (v >= b.virtualStart && v <= b.virtualStart + b.lines - 1) {
      return b.fileStart + (v - b.virtualStart);
    }
  }
  return null; // faellt auf Trennzeile o.ae. — sollte nicht vorkommen
}

// --- Linten ---
const linter = new Linter();
const config = {
  languageOptions: {
    ecmaVersion: 2022,
    sourceType: "script",
    parserOptions: { ecmaFeatures: { jsx: true } },
    globals: {
      ...globals.browser,
      React: "readonly", ReactDOM: "readonly", XLSX: "readonly",
      supabase: "readonly", Babel: "readonly",
      JSRCalc: "readonly",   // geteilte Rechenkerne aus shared/jsr-calc.js (externes Script)
    },
  },
  plugins: { react },
  rules: {
    "no-undef": "error",
    "no-unused-vars": ["warn", { args: "none", caughtErrors: "none", ignoreRestSiblings: true }],
    // markiert JSX-genutzte Komponenten + React selbst als "verwendet"
    "react/jsx-uses-vars": "error",
    "react/jsx-uses-react": "error",
  },
};

let messages;
try {
  messages = linter.verify(virtual, config);
} catch (err) {
  console.log("  ✗ Linter-Abbruch: " + (err && err.message ? err.message : err));
  console.log("RESULT: FAIL");
  process.exit(1);
}

const rel = path.relative(root, file);
const errors = [], warns = [];
for (const msg of messages) {
  const fileLine = toFileLine(msg.line);
  const loc = (fileLine == null ? "virt#" + msg.line : rel + ":" + fileLine) + ":" + msg.column;
  const rec = { rule: msg.ruleId || "parse", text: msg.message, loc, fatal: !!msg.fatal };
  (msg.severity === 2 ? errors : warns).push(rec);
}

// Fatale Parse-Fehler zaehlen als Fehler (haben severity 2, ruleId null)
if (errors.length) {
  console.log("  no-undef / Fehler:");
  for (const e of errors) console.log("  ✗ [" + e.rule + "] " + e.text + "\n    -> " + e.loc);
}
if (warns.length) {
  console.log("  no-unused-vars / Warnungen (blockieren NICHT): " + warns.length);
  for (const w of warns) console.log("  ⚠ " + w.text + "\n    -> " + w.loc);
}

const ok = errors.length === 0;
console.log("gelintet: 1 virtuelle Datei aus " + blocks.length + " Inline-Scripts   Fehler: " + errors.length + "   Warnungen: " + warns.length + "   " + (ok ? "ok" : "NO-UNDEF"));
console.log("RESULT:", ok ? "PASS" : "FAIL");
process.exit(ok ? 0 : 1);
