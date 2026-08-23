#!/usr/bin/env node
// tdzcheck.js — faengt die Klasse "eager Temporal Dead Zone": eine const/let-Variable wird im SELBEN
// Funktionskoerper VOR ihrer Deklaration benutzt (eager, nicht in einer verschachtelten Funktion).
// Das ist ein Laufzeit-`ReferenceError: Cannot access 'X' before initialization` — KEIN Syntaxfehler,
// den jsxcheck/syntaxcheck sehen. Zweimal am 2026-08-23 aufgetreten (myAssign in DailyTasksView, M im Cockpit),
// beide sperrten nach dem Login aus (Cockpit/Startseite laedt sofort).
//
// Warum nicht einfach eslint `no-use-before-define`? Das meldet AUCH harmlose Faelle: Modul-Singletons wie `sb`
// (146x) werden INNERHALB von Funktionen benutzt, die spaeter laufen — kein TDZ. Zu laut zum Blocken.
// Dieser Check unterscheidet per Scope: gefaehrlich nur, wenn zwischen Referenz und Deklaration KEINE
// Funktions-Scope liegt (dann laeuft die Referenz in derselben synchronen Auswertung wie die Deklaration).
//
// Exit 0 = kein eager-TDZ. Exit 1 = Fund ODER Tooling fehlt.

const fs = require("fs"), cp = require("child_process"), path = require("path");
let root = "."; try { root = cp.execSync("git rev-parse --show-toplevel").toString().trim(); } catch (e) {}
const here = __dirname;

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
  try { cp.execSync("npm install", { cwd: here, stdio: "ignore" }); } catch (e) {}
  tools = loadDeps();
  if (!tools) { console.log("RESULT: FAIL  (eslint-Tooling fehlt — 'cd scripts/checks && npm install')"); process.exit(1); }
}
const { Linter, react, globals } = tools;

const file = process.argv[2] || path.join(root, "frontend/hr.html");
const s = fs.readFileSync(file, "utf8");

// Inline-JS-Bloecke zu EINER virtuellen Datei fuegen (wie eslintcheck), Zeilen-Map fuehren.
const openRe = /<script([^>]*)>/g;
function isInlineJs(attrs) {
  if (/\bsrc=/.test(attrs)) return false;
  const t = attrs.match(/type=["']([^"']+)["']/);
  if (!t) return true;
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
  const fileStart = s.slice(0, bodyStart).split("\n").length;
  if (virtual && !virtual.endsWith("\n")) virtual += "\n";
  const virtualStart = virtual.split("\n").length;
  virtual += body;
  if (!virtual.endsWith("\n")) virtual += "\n";
  virtual += ";\n";
  blocks.push({ virtualStart, fileStart, lines: body.split("\n").length });
}
function toFileLine(v) {
  for (const b of blocks) { if (v >= b.virtualStart && v <= b.virtualStart + b.lines - 1) return b.fileStart + (v - b.virtualStart); }
  return null;
}

// Custom-Regel: eager use-before-declaration von const/let.
const tdzPlugin = {
  rules: {
    "eager": {
      create(context) {
        const sourceCode = context.sourceCode || context.getSourceCode();
        return {
          "Program:exit"() {
            const sm = sourceCode.scopeManager;
            const visit = (scope) => {
              for (const v of scope.variables) {
                const def = v.defs && v.defs[0];
                if (!def || def.type !== "Variable") continue;
                const kind = def.parent && def.parent.kind;
                if (kind !== "const" && kind !== "let") continue;
                const declId = def.name;
                if (!declId || !declId.range) continue;
                const declStart = declId.range[0];
                for (const ref of v.references) {
                  const rid = ref.identifier;
                  if (!rid || !rid.range || rid.range[0] >= declStart || rid === declId) continue; // nach Deklaration = ok
                  // eager, wenn zwischen ref.from und v.scope KEINE Funktions-Scope liegt.
                  let sc = ref.from, eager = false;
                  while (sc) {
                    if (sc === v.scope) { eager = true; break; }
                    if (sc.type === "function") break; // verschachtelte Funktion -> spaeter -> harmlos
                    sc = sc.upper;
                  }
                  if (eager) context.report({ node: rid, message: "'" + v.name + "' vor der Deklaration benutzt (gleiche Funktion, eager) -> TDZ-Crash-Risiko." });
                }
              }
              scope.childScopes.forEach(visit);
            };
            visit(sm.globalScope);
          }
        };
      }
    }
  }
};

const linter = new Linter();
const config = {
  languageOptions: { ecmaVersion: 2022, sourceType: "script", parserOptions: { ecmaFeatures: { jsx: true } },
    globals: { ...globals.browser, React: "readonly", ReactDOM: "readonly", XLSX: "readonly", supabase: "readonly", Babel: "readonly", JSRCalc: "readonly" } },
  plugins: { react, tdz: tdzPlugin },
  rules: { "tdz/eager": "error", "react/jsx-uses-vars": "error", "react/jsx-uses-react": "error" },
};

let messages;
try { messages = linter.verify(virtual, config); }
catch (err) { console.log("  ✗ Linter-Abbruch: " + (err && err.message ? err.message : err)); console.log("RESULT: FAIL"); process.exit(1); }

const rel = path.relative(root, file);
const hits = messages.filter(x => x.ruleId === "tdz/eager");
for (const h of hits) {
  const fl = toFileLine(h.line);
  console.log("  ✗ " + h.message + "\n    -> " + (fl == null ? "virt#" + h.line : rel + ":" + fl) + ":" + h.column);
}
const ok = hits.length === 0;
console.log("tdzcheck: " + blocks.length + " Inline-Scripts, eager-TDZ-Funde: " + hits.length + "   " + (ok ? "ok" : "TDZ"));
console.log("RESULT:", ok ? "PASS" : "FAIL");
process.exit(ok ? 0 : 1);
