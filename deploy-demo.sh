#!/bin/bash
# Reisewelt-Demo Deploy — baut Demo-Varianten der Portale (Supabase → Myna-Projekt, Portal-Links → /demo)
# und pusht sie nach /var/www/tive360/demo. Berührt die Produktions-Portale NICHT.
set -e

SERVER="root@178.104.147.208"
LOCAL_DIR="./frontend"
REMOTE_BASE="/var/www/tive360"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRECOMPILE="$SCRIPT_DIR/scripts/precompile/precompile.js"
MYNA_URL="https://ggznzbfauuqljoefwwop.supabase.co"
MYNA_KEY="sb_publishable_chzNoezONMRBWimrT3MHZQ_scnVYzBb"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "=== Reisewelt-Demo Deploy (Myna-Projekt) ==="

demoize() {  # $1 = Quell-HTML → stdout: Demo-Variante (SB→Myna, Portal-Links→/demo, kein HolidayCheck-Seed)
  # Kaltstart-Fix: das HolidayCheck-Seed-Skript durch ein Aufräum-Skript ersetzen (setzt jsr_projects_v1='[]' →
  # Projekt-State startet LEER statt HolidayCheck, wird dann aus Myna mit Reisewelt gefüllt; nie Stale-Werte im Termin).
  # Außerdem employees-Ladetimeout hoch (kalter Myna braucht länger als 18s).
  perl -0pe 's|<script id="jsr-seed-holidaycheck">.*?</script>|<script id="jsr-seed-holidaycheck">(function(){try{localStorage.setItem("jsr_projects_v1","[]");localStorage.setItem("jsr_employees_v1","[]");localStorage.removeItem("jsr_emp_v3");localStorage.removeItem("jsr_kpi_cfg_v1");}catch(e){}})();</script>|s' "$1" \
  | sed -e "s|https://msdiyjxckmpvuomnhvjp.supabase.co|$MYNA_URL|g" \
      -e "s|sb_publishable_exKYOG6Znhj_JlO0v6erQQ_q0HWWiyl|$MYNA_KEY|g" \
      -e "s|https://client.tive360.de/|/demo/client/|g" \
      -e "s|https://mitarbeiter.tive360.de/|/demo/mitarbeiter/|g" \
      -e "s|https://hr.tive360.de/|/demo/hr/|g" \
      -e "s|async function loadEmployeesFromDB(timeoutMs=18000)|async function loadEmployeesFromDB(timeoutMs=45000)|g" \
      -e "s|__BUILD_ID__|demo|g"
}

ssh "$SERVER" "mkdir -p $REMOTE_BASE/demo/hr $REMOTE_BASE/demo/mitarbeiter $REMOTE_BASE/demo/client"

echo "→ HR-Portal (Precompile, Myna)…"
demoize "$LOCAL_DIR/hr.html" > "$TMP/hr.src"
node --no-warnings "$PRECOMPILE" "$TMP/hr.src" > "$TMP/hr.html" || { echo "✗ Precompile hr fehlgeschlagen"; exit 1; }
rsync -az "$TMP/hr.html" "$SERVER:$REMOTE_BASE/demo/hr/index.html"

echo "→ Client-Portal (Precompile, Myna)…"
demoize "$LOCAL_DIR/client.html" > "$TMP/client.src"
node --no-warnings "$PRECOMPILE" "$TMP/client.src" > "$TMP/client.html" || { echo "✗ Precompile client fehlgeschlagen"; exit 1; }
rsync -az "$TMP/client.html" "$SERVER:$REMOTE_BASE/demo/client/index.html"

echo "→ Mitarbeiter-Portal (Myna)…"
demoize "$LOCAL_DIR/mitarbeiter.html" > "$TMP/mitarbeiter.html"
rsync -az "$TMP/mitarbeiter.html" "$SERVER:$REMOTE_BASE/demo/mitarbeiter/index.html"

echo "→ Zusatz-Seiten (showcase/termin/praesentation)…"
for f in showcase termin praesentation; do
  [ -f "$LOCAL_DIR/$f.html" ] && demoize "$LOCAL_DIR/$f.html" > "$TMP/$f.html" && rsync -az "$TMP/$f.html" "$SERVER:$REMOTE_BASE/demo/client/$f.html" || true
done

echo "→ Assets + shared…"
for d in hr mitarbeiter client; do
  rsync -az "$LOCAL_DIR/assets/" "$SERVER:$REMOTE_BASE/demo/$d/assets/"
  rsync -az "$LOCAL_DIR/shared/" "$SERVER:$REMOTE_BASE/demo/$d/shared/"
done

echo "→ Landing (/demo)…"
demoize "$SCRIPT_DIR/demo/demo-landing.html" > "$TMP/index.html"
rsync -az "$TMP/index.html" "$SERVER:$REMOTE_BASE/demo/index.html"

echo ""
echo "✓ Demo deployt → https://tive360.de/demo"
echo "  (Caddy /demo-Route muss aktiv sein.)"
