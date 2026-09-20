#!/usr/bin/env bash
# Phase 4 - deploy n8n.
#
#   bash deploy.sh <subdomain>.duckdns.org [timezone]        # public: n8n behind Caddy
#   bash deploy.sh --tailscale <name>.ts.net [timezone]      # private: n8n behind tailscale serve
#
# Idempotent, and deliberately refuses to regenerate an existing encryption key.
set -euo pipefail

MODE=public
if [[ "${1:-}" == "--tailscale" ]]; then MODE=tailscale; shift; fi

DOMAIN="${1:?usage: deploy.sh [--tailscale] <domain> [timezone]}"
TZ_NAME="${2:-Europe/Dublin}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HOME/n8n"

case "$DOMAIN" in
  http*|*/) echo "DOMAIN must be a bare hostname - no scheme, no trailing slash." >&2; exit 1;;
esac

mkdir -p "$DEST/files"

if [[ $MODE == tailscale ]]; then
  cp "$SRC/docker-compose.tailscale.yml" "$DEST/docker-compose.yml"
  rm -f "$DEST/Caddyfile"
else
  cp "$SRC/docker-compose.yml" "$DEST/docker-compose.yml"
  sed "s/__DOMAIN__/$DOMAIN/" "$SRC/Caddyfile.template" > "$DEST/Caddyfile"
fi

if [[ -f "$DEST/.env" ]]; then
  echo "$DEST/.env exists - keeping it (the encryption key in it must not change)."
  grep -q "^DOMAIN=$DOMAIN$" "$DEST/.env" || echo "NOTE: DOMAIN in .env differs from $DOMAIN - edit it by hand if that is wrong."
else
  cat > "$DEST/.env" <<EOF
DOMAIN=$DOMAIN
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
GENERIC_TIMEZONE=$TZ_NAME
N8N_LOG_LEVEL=warn
EXECUTIONS_DATA_MAX_AGE=168
EOF
  chmod 600 "$DEST/.env"
  echo "Generated $DEST/.env with a fresh encryption key."
  echo "BACK THAT KEY UP. Without it, stored credentials are unrecoverable."
fi

cd "$DEST"
docker compose up -d

if [[ $MODE == tailscale ]]; then
  echo
  echo "== Publishing on the tailnet over HTTPS"
  sudo tailscale cert "$DOMAIN" >/dev/null
  sudo tailscale serve --bg 5678
  sudo tailscale serve status
  echo
  echo "Open https://$DOMAIN from any device signed in to your tailnet."
  echo "Create the owner account now - do not leave it unclaimed."
  echo
  echo "Note: webhooks are reachable only from inside your tailnet. To accept"
  echo "calls from outside services, expose ONLY the webhook path publicly:"
  echo "  sudo tailscale funnel --bg --set-path /webhook http://localhost:5678/webhook"
  echo "That leaves the editor UI private. Do not funnel the whole service."
else
  echo
  echo "Watching Caddy for the certificate. Look for 'certificate obtained successfully'."
  echo "Ctrl-C once you see it (the containers keep running)."
  docker compose logs -f caddy
fi
