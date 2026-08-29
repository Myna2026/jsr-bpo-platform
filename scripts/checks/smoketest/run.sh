#!/usr/bin/env bash
# Startet einen lokalen Static-Server auf frontend/ (testet den NEUEN Stand vor dem Deploy),
# laesst den Smoke-Test dagegen laufen und raeumt den Server wieder ab.
# Exit 0 = ok · 1 = Absturz gefunden (blockt) · 2 = konnte nicht laufen (Warnung, kein Block).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
PORT="${SMOKE_PORT:-8799}"

if [ ! -d "$HERE/node_modules/playwright" ]; then
  echo "smoketest: playwright nicht installiert (scripts/checks/smoketest: npm install) -> uebersprungen."
  exit 2
fi

python3 -m http.server "$PORT" --directory "$ROOT/frontend" >/dev/null 2>&1 &
SRV=$!
trap 'kill $SRV >/dev/null 2>&1' EXIT

# auf den Server warten
for i in $(seq 1 20); do
  if curl -sf "http://localhost:$PORT/hr.html" >/dev/null 2>&1; then break; fi
  sleep 0.3
done

SMOKE_URL="http://localhost:$PORT/hr.html" node "$HERE/smoke.mjs"
exit $?
