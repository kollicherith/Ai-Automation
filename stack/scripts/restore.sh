#!/usr/bin/env bash
# Rebuild n8n from a backup produced by backup-n8n.sh.
#   bash restore.sh ~/backups/n8n-2026-09-20.tar.gz.age [identity-file]
#
# On a fresh VM: run bootstrap.sh and harden.sh first, put your age private key
# at ~/.config/n8n-backup/identity.txt (from your password manager), then run
# this. It restores .env - and therefore N8N_ENCRYPTION_KEY - which is what
# makes the exported credentials readable again.
set -euo pipefail

ARCHIVE="${1:?usage: restore.sh <backup.tar.gz[.age]> [identity-file]}"
IDENTITY="${2:-$HOME/.config/n8n-backup/identity.txt}"
DEST="$HOME/n8n"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

[[ -f "$ARCHIVE" ]] || { echo "no such archive: $ARCHIVE" >&2; exit 1; }

if [[ "$ARCHIVE" == *.age ]]; then
  [[ -f "$IDENTITY" ]] || { echo "need the age private key at $IDENTITY" >&2; exit 1; }
  age -d -i "$IDENTITY" -o "$WORK/backup.tar.gz" "$ARCHIVE"
  TAR="$WORK/backup.tar.gz"
else
  TAR="$ARCHIVE"
fi

if [[ -f "$DEST/.env" ]]; then
  cp "$DEST/.env" "$DEST/.env.before-restore-$(date +%s)"
  echo "existing .env saved alongside as .env.before-restore-*"
fi

mkdir -p "$DEST"
tar xzf "$TAR" -C "$DEST"
chmod 600 "$DEST/.env"
echo "restored config to $DEST"

cd "$DEST"
docker compose up -d
sleep 10

# Workflows and credentials go back in through the CLI, decrypted by the
# N8N_ENCRYPTION_KEY that just came back with .env.
shopt -s nullglob
for f in "$DEST"/files/workflows-*.json;   do docker compose exec -T n8n n8n import:workflow   --input="/files/$(basename "$f")"; done
for f in "$DEST"/files/credentials-*.json; do docker compose exec -T n8n n8n import:credentials --input="/files/$(basename "$f")"; done

echo
echo "Restored. Check the UI, then delete the plaintext exports:"
echo "  rm -f ~/n8n/files/workflows-*.json ~/n8n/files/credentials-*.json"
