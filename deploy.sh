#!/bin/bash
# TIVE 360° Deploy-Script
# Pusht die Frontend-Files auf die Hetzner-VM

set -e  # Bei Fehler abbrechen

SERVER="root@178.104.147.208"
LOCAL_DIR="./frontend"
REMOTE_BASE="/var/www/tive360"

echo "=== TIVE 360° Deploy ==="
echo "Server: $SERVER"
echo ""

# hr.html → /var/www/tive360/hr/index.html
echo "→ HR-Portal..."
rsync -az --progress "$LOCAL_DIR/hr.html" "$SERVER:$REMOTE_BASE/hr/index.html"

# mitarbeiter.html → /var/www/tive360/mitarbeiter/index.html
echo "→ Mitarbeiter-Portal..."
rsync -az --progress "$LOCAL_DIR/mitarbeiter.html" "$SERVER:$REMOTE_BASE/mitarbeiter/index.html"

# client.html → /var/www/tive360/client/index.html
echo "→ Client-Portal..."
rsync -az --progress "$LOCAL_DIR/client.html" "$SERVER:$REMOTE_BASE/client/index.html"

# showcase.html → /var/www/tive360/client/showcase.html (öffentliche Token-Seite, login-los)
# Caddy file_server liefert Geschwisterdateien direkt aus → client.tive360.de/showcase.html
echo "→ Showcase (öffentlich)..."
rsync -az --progress "$LOCAL_DIR/showcase.html" "$SERVER:$REMOTE_BASE/client/showcase.html"

# root-index.html → /var/www/tive360/root/index.html (Marketing-Landing)
# root-login.html → /var/www/tive360/root/login.html (universeller Login)
echo "→ Root (Landing + Login)..."
ssh "$SERVER" "mkdir -p $REMOTE_BASE/root"
rsync -az --progress "$LOCAL_DIR/root-index.html" "$SERVER:$REMOTE_BASE/root/index.html"
rsync -az --progress "$LOCAL_DIR/root-login.html" "$SERVER:$REMOTE_BASE/root/login.html"

# stempel.html → HR-Subdomain (hr.tive360.de/stempel.html) + Root-Domain (tive360.de/stempel.html)
echo "→ Stempeluhr..."
rsync -az --progress "$LOCAL_DIR/stempel.html" "$SERVER:$REMOTE_BASE/hr/stempel.html"
rsync -az --progress "$LOCAL_DIR/stempel.html" "$SERVER:$REMOTE_BASE/root/stempel.html"

# assets/ (tive360-mark.svg = Logo + Favicon) → auf jede Subdomain-Root, weil
# der Favicon-Pfad /assets/... pro Subdomain aufgelöst wird. Behebt die 404s.
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
