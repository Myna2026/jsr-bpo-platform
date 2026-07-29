// Precompile für den Deploy: übersetzt die <script type="text/babel">-Blöcke EINMAL lokal (mit dem
// gepinnten @babel/standalone 7.x, classic React.createElement + retainLines), sodass der Browser fertiges
// JS bekommt — kein Babel-Download, keine In-Browser-Übersetzung mehr. Entfernt den @babel/standalone-Loader
// und schaltet React auf die Production-Builds. Liest eine HTML-Datei (arg1), schreibt das Kompilat nach stdout.
// Die Quelldatei bleibt unangetastet — nur die Deploy-Ausgabe wird transformiert (deploy.sh nutzt eine Temp-Kopie).
//
// runtime:'classic' ist zwingend: der Code nutzt window.React (UMD), NICHT das automatische jsx-runtime.
// retainLines:true hält die Zeilennummern ≈ deckungsgleich zur Quelle → Stacktraces zeigen auf ~dieselbe Zeile.
const fs = require('fs');
const path = require('path');
const Babel = require(path.join(__dirname, 'babel.min.js'));

const inFile = process.argv[2];
if (!inFile) { console.error('Usage: node precompile.js <input.html>'); process.exit(2); }
const name = path.basename(inFile);
let html = fs.readFileSync(inFile, 'utf8');

const OPT = { presets: [['react', { runtime: 'classic' }]], retainLines: true, compact: false, comments: true };

// 1) text/babel-Blöcke übersetzen. Nicht-gierig bis zum ersten </script> ist korrekt: ein literales
//    </script> im Block würde schon den Browser-Parser brechen, existiert also nicht.
let count = 0, failed = 0;
html = html.replace(/<script type="text\/babel">([\s\S]*?)<\/script>/g, (whole, code) => {
  count++;
  try { return '<script>' + Babel.transform(code, OPT).code + '</script>'; }
  catch (e) { failed++; console.error('✗ ' + name + ' Babel-Block #' + count + ': ' + String(e.message || e).split('\n')[0]); return whole; }
});
if (failed) { console.error('✗ ' + name + ': ' + failed + ' Block/Blöcke fehlgeschlagen — Abbruch.'); process.exit(1); }

// 2) @babel/standalone-Loader entfernen (im Browser nicht mehr nötig, spart ~546 KB Download).
html = html.replace(/<script src="https:\/\/unpkg\.com\/@babel\/standalone\/babel\.min\.js"><\/script>/g, '');

// 3) React → Production-Builds (kleiner + schneller; keine Dev-Warnungen im Einsatz).
html = html
  .replace(/react@18\/umd\/react\.development\.js/g, 'react@18/umd/react.production.min.js')
  .replace(/react-dom@18\/umd\/react-dom\.development\.js/g, 'react-dom@18/umd/react-dom.production.min.js');

// 4) 7. Check: jeder ausgelieferte Inline-<script>-Block muss als JS parsen. Fehler = Abbruch (nichts wird
//    deployt). Die __BUILD_ID__-Ersetzung passiert erst in deploy.sh danach — der Platzhalter parst als String.
let checked = 0;
const scriptRe = /<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g;
let m;
while ((m = scriptRe.exec(html))) {
  const body = m[1].trim();
  if (!body) continue;                       // externe <script src=…> haben keinen Body
  try { Babel.transform(body, { compact: false, code: false }); checked++; }
  catch (e) { console.error('✗ ' + name + ': kompiliertes <script> parst nicht: ' + String(e.message || e).split('\n')[0]); process.exit(1); }
}

process.stdout.write(html);
console.error('✓ ' + name + ': ' + count + ' Babel-Block(e) kompiliert · ' + checked + ' Inline-Script(s) validiert · React=prod · Babel-Loader entfernt.');
