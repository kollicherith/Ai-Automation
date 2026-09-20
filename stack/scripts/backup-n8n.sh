#!/usr/bin/env bash
# Phase 6 - nightly backup, encrypted at rest.
#
# Install:
#   cp backup-n8n.sh ~/backup-n8n.sh && chmod +x ~/backup-n8n.sh
#   (crontab -l 2>/dev/null; echo "0 3 * * * ~/backup-n8n.sh >> ~/backups/backup.log 2>&1") | crontab -
#
# The archive contains DECRYPTED credentials and N8N_ENCRYPTION_KEY. Run
# harden.sh first to generate the age keypair, and this script encrypts to it so
# the file is safe to copy anywhere. Restore with restore.sh.
#
# Optional off-VM copy: set BACKUP_REMOTE to an rclone remote path, e.g.
#   BACKUP_REMOTE=gdrive:n8n-backups
# A backup that only exists on the machine you might lose is not a backup.
set -euo pipefail

cd ~/n8n
mkdir -p ~/backups
STAMP=$(date +%F)
KEYDIR="$HOME/.config/n8n-backup"
PLAIN=~/backups/n8n-$STAMP.tar.gz

docker compose exec -T n8n n8n export:workflow --all --output=/files/workflows-$STAMP.json
docker compose exec -T n8n n8n export:credentials --all --output=/files/credentials-$STAMP.json

tar czf "$PLAIN" -C ~/n8n files .env Caddyfile docker-compose.yml 2>/dev/null \
  || tar czf "$PLAIN" -C ~/n8n files .env docker-compose.yml   # no Caddyfile in Tailscale mode
chmod 600 "$PLAIN"

# Exports are inside the archive now; do not leave plaintext credentials lying
# around in a directory that workflows can read.
rm -f ~/n8n/files/workflows-$STAMP.json ~/n8n/files/credentials-$STAMP.json

FINAL="$PLAIN"
if [[ -f "$KEYDIR/recipient.txt" ]] && command -v age >/dev/null 2>&1; then
  age -R "$KEYDIR/recipient.txt" -o "$PLAIN.age" "$PLAIN"
  chmod 600 "$PLAIN.age"
  shred -u "$PLAIN" 2>/dev/null || rm -f "$PLAIN"
  FINAL="$PLAIN.age"
else
  echo "WARNING: not encrypted - no age key found. Run harden.sh." >&2
  echo "WARNING: $PLAIN holds decrypted credentials. Do not copy it anywhere." >&2
fi

if [[ -n "${BACKUP_REMOTE:-}" ]]; then
  if [[ "$FINAL" != *.age ]]; then
    echo "REFUSING to upload an unencrypted backup. Run harden.sh first." >&2
    exit 1
  fi
  rclone copy "$FINAL" "$BACKUP_REMOTE/" && echo "copied off-VM to $BACKUP_REMOTE"
fi

find ~/backups -name 'n8n-*.tar.gz*' -mtime +14 -delete
echo "$(date -Is) backup ok: $FINAL ($(du -h "$FINAL" | cut -f1))"
