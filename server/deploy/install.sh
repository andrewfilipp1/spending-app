#!/usr/bin/env bash
# Installs/updates the sync server on a Debian/Ubuntu VPS. Run as root from the server/ folder:
#   sudo bash deploy/install.sh sync.example.com
# Idempotent: running it again updates the code and restarts the service; data is kept.
set -euo pipefail
DOMAIN="${1:?usage: install.sh <domain>}"
SRC="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v node >/dev/null || [ "$(node -p 'process.versions.node.split(".")[0]')" -lt 22 ]; then
  echo "→ Installing Node.js 24"
  curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
  apt-get install -y nodejs
fi

if ! command -v caddy >/dev/null; then
  echo "→ Installing Caddy"
  apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update && apt-get install -y caddy
fi

echo "→ Copying code to /opt/spending-sync"
install -d -m 0755 /opt/spending-sync/src
install -m 0644 "$SRC/schema.sql" "$SRC/package.json" /opt/spending-sync/
install -m 0644 "$SRC"/src/*.js /opt/spending-sync/src/

install -m 0644 "$SRC/deploy/spending-sync.service" /etc/systemd/system/spending-sync.service
systemctl daemon-reload
systemctl enable --now spending-sync
systemctl restart spending-sync

echo "→ Configuring Caddy for $DOMAIN"
install -d /etc/caddy/sites
sed "s/sync.example.com/$DOMAIN/" "$SRC/deploy/Caddyfile" > /etc/caddy/sites/spending-sync.caddy
grep -q 'import sites/\*' /etc/caddy/Caddyfile 2>/dev/null || echo 'import sites/*' >> /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
systemctl reload caddy || systemctl restart caddy

sleep 2
curl -fsS "http://127.0.0.1:8787/v1/health" && echo " ← local OK"
echo "Done. Check https://$DOMAIN/v1/health from your computer."
