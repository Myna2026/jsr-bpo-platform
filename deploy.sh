#!/bin/bash
# TIVE 360° Deploy-Script — pusht die Frontend-Files auf die Hetzner-VM.
#
# Zwei Sicherungsstufen (System ist produktiv):
#   Stufe 3  Vorab-Pruefung: jsxcheck/syntaxcheck/macheck/fieldcheck/eslintcheck laufen ZUERST.
#            syntaxcheck parst hr.html echt (JSX) — faengt Fehler, die reine Klammerzaehlung nicht sieht.
#            eslintcheck lintet alle Inline-Scripts als eine virtuelle Datei: no-undef blockt (verwaiste
#            Referenzen), no-unused-vars warnt nur (Warnungen sichtbar via 'node scripts/checks/eslintcheck.js').
#            Ein Fehlschlag bricht sofort ab — es wird NICHTS uebertragen.
#            Notausgang: ./deploy.sh --force  (Pruefung uebersprungen, mit Warnung)
#   Stufe 1  Rollback: vor jedem Uebertragen wird der aktuelle Live-Stand nach
#            /var/www/tive360/_backups/<Zeitstempel>/ gesichert (letzte 10 behalten).
#            Zuruecksetzen mit ./rollback.sh
set -e

SERVER="root@178.104.147.208"
LOCAL_DIR="./frontend"
REMOTE_BASE="/var/www/tive360"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKS="$SCRIPT_DIR/scripts/checks"
KEEP=10

FORCE=0
if [ "$1" = "--force" ]; then FORCE=1; fi

echo "=== TIVE 360° Deploy ==="
echo "Server: $SERVER"
echo ""

# ── Stufe 3: Vorab-Pruefung ────────────────────────────────────────────────
if [ "$FORCE" = "1" ]; then
  echo "⚠  --force: VORAB-PRUEFUNG WIRD UEBERSPRUNGEN — kein Netz gegen kaputte Dateien."
  echo "⚠  Nur im Notfall verwenden. Weiter in 2s…"
  sleep 2
  echo ""
else
  echo "→ Vorab-Pruefung (Abbruch bei Fehler)…"
  run_check() {
    label="$1"; shift
    printf "  %-30s " "$label"
    if "$@" > /tmp/tive_check.out 2>&1; then
      echo "OK"
    else
      echo "FEHLGESCHLAGEN"
      echo ""
      echo "✗ ABBRUCH — Check '$label' ist gescheitert. Es wurde NICHTS uebertragen."
      echo "────────────────────────────────────────────────────────────"
      cat /tmp/tive_check.out
      echo "────────────────────────────────────────────────────────────"
      echo "Ursache beheben und erneut deployen."
      echo "Falls die Baseline BEWUSST verschoben wurde: im jeweiligen Skript"
      echo "(scripts/checks/) anpassen. Notausgang (nur im Notfall): ./deploy.sh --force"
      exit 1
    fi
  }
  run_check "jsxcheck.js  (hr.html)"           node    "$CHECKS/jsxcheck.js"
  run_check "syntaxcheck.js (alle Inline-Skripte + Tag-Balance)" node "$CHECKS/syntaxcheck.js"
  run_check "macheck.js   (mitarbeiter.html)"  node    "$CHECKS/macheck.js"
  run_check "fieldcheck.py (Felder/Migration)" python3 "$CHECKS/fieldcheck.py"
  run_check "eslintcheck.js (hr.html no-undef)" node    "$CHECKS/eslintcheck.js"
  echo "  → alle Checks bestanden."
  echo ""
fi

# ── Stufe 1: Backup des aktuellen Live-Stands (vor dem Ueberschreiben) ──────
echo "→ Backup des aktuellen Live-Stands…"
PRUNE_FROM=$((KEEP + 1))
TS=$(ssh "$SERVER" "ts=\$(date +%Y-%m-%d_%H%M%S); bk=$REMOTE_BASE/_backups/\$ts; mkdir -p \$bk; for d in hr mitarbeiter client root; do [ -d $REMOTE_BASE/\$d ] && cp -a $REMOTE_BASE/\$d \$bk/; done; ls -1dt $REMOTE_BASE/_backups/*/ 2>/dev/null | tail -n +$PRUNE_FROM | xargs -r rm -rf; echo \$ts")
echo "  gesichert: $REMOTE_BASE/_backups/$TS  (die letzten $KEEP Staende bleiben erhalten)"
echo ""

# ── Uebertragen ────────────────────────────────────────────────────────────
# ── Build-Stempel: Platzhalter __BUILD_ID__ → Deploy-Zeitstempel. Sichtbar via console.info
#    ("TIVE build …") + window.TIVE_BUILD. Damit ist "echter Bug vs. alter Browser-Cache" sofort klaerbar.
BUILD="$TS"
STAMP_TMP="$(mktemp -d)"
trap 'rm -rf "$STAMP_TMP"' EXIT
PRECOMPILE="$SCRIPT_DIR/scripts/precompile/precompile.js"
stamp_rsync() {  # ohne Babel: nur __BUILD_ID__ stempeln (mitarbeiter.html ist reines JS)
  local base; base="$(basename "$1")"
  sed "s/__BUILD_ID__/$BUILD/g" "$1" > "$STAMP_TMP/$base"
  rsync -az --progress "$STAMP_TMP/$base" "$SERVER:$2"
}
compile_stamp_rsync() {  # mit Babel-Precompile (hr/client): uebersetzen+validieren → stempeln → rsync.
  local base; base="$(basename "$1")"
  node --no-warnings "$PRECOMPILE" "$1" > "$STAMP_TMP/$base.pre" || { echo "✗ Precompile $base fehlgeschlagen — nichts uebertragen."; exit 1; }
  sed "s/__BUILD_ID__/$BUILD/g" "$STAMP_TMP/$base.pre" > "$STAMP_TMP/$base"
  rsync -az --progress "$STAMP_TMP/$base" "$SERVER:$2"
}
echo "  Build-Kennung: $BUILD"
echo ""

echo "→ HR-Portal (Precompile)..."
compile_stamp_rsync "$LOCAL_DIR/hr.html" "$REMOTE_BASE/hr/index.html"

echo "→ Mitarbeiter-Portal..."
stamp_rsync "$LOCAL_DIR/mitarbeiter.html" "$REMOTE_BASE/mitarbeiter/index.html"

echo "→ Client-Portal (Precompile)..."
compile_stamp_rsync "$LOCAL_DIR/client.html" "$REMOTE_BASE/client/index.html"

echo "→ Showcase (öffentlich)..."
rsync -az --progress "$LOCAL_DIR/showcase.html" "$SERVER:$REMOTE_BASE/client/showcase.html"

echo "→ Root (Landing + Login)..."
ssh "$SERVER" "mkdir -p $REMOTE_BASE/root"
rsync -az --progress "$LOCAL_DIR/root-index.html" "$SERVER:$REMOTE_BASE/root/index.html"
rsync -az --progress "$LOCAL_DIR/root-login.html" "$SERVER:$REMOTE_BASE/root/login.html"

echo "→ Stempeluhr..."
rsync -az --progress "$LOCAL_DIR/stempel.html" "$SERVER:$REMOTE_BASE/hr/stempel.html"
rsync -az --progress "$LOCAL_DIR/stempel.html" "$SERVER:$REMOTE_BASE/root/stempel.html"

echo "→ Assets (Logo/Favicon)..."
rsync -az --progress "$LOCAL_DIR/assets/" "$SERVER:$REMOTE_BASE/hr/assets/"
rsync -az --progress "$LOCAL_DIR/assets/" "$SERVER:$REMOTE_BASE/mitarbeiter/assets/"
rsync -az --progress "$LOCAL_DIR/assets/" "$SERVER:$REMOTE_BASE/client/assets/"
rsync -az --progress "$LOCAL_DIR/assets/" "$SERVER:$REMOTE_BASE/root/assets/"

echo ""
echo "✓ Deploy erfolgreich"
echo "  https://tive360.de"
echo "  https://hr.tive360.de"
echo "  https://mitarbeiter.tive360.de"
echo "  https://client.tive360.de"
echo "  https://client.tive360.de/showcase.html (öffentlich, Token)"
echo ""
echo "↩  Rollback bei Problemen:  ./rollback.sh"
echo "   (dieser vorherige Stand ist gesichert als $TS)"
