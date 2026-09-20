#!/usr/bin/env bash
# Phase 6 - nightly backup. Install with:
#   cp backup-n8n.sh ~/backup-n8n.sh && chmod +x ~/backup-n8n.sh
#   (crontab -l 2>/dev/null; echo "0 3 * * * ~/backup-n8n.sh >> ~/backups/backup.log 2>&1") | crontab -
#
# The tarball contains DECRYPTED credentials and the encryption key. Treat it as
# a secret, and copy it off the VM - a backup that only exists on the machine you
# might lose is not a backup.
set -euo pipefail

cd ~/n8n
mkdir -p ~/backups
STAMP=$(date +%F)

docker compose exec -T n8n n8n export:workflow --all --output=/files/workflows-$STAMP.json
docker compose exec -T n8n n8n export:credentials --all --output=/files/credentials-$STAMP.json

tar czf ~/backups/n8n-$STAMP.tar.gz -C ~/n8n files .env Caddyfile docker-compose.yml
chmod 600 ~/backups/n8n-$STAMP.tar.gz

# The exports inside ./files are already captured in the tarball.
rm -f ~/n8n/files/workflows-$STAMP.json ~/n8n/files/credentials-$STAMP.json

find ~/backups -name 'n8n-*.tar.gz' -mtime +14 -delete
echo "$(date -Is) backup ok: ~/backups/n8n-$STAMP.tar.gz ($(du -h ~/backups/n8n-$STAMP.tar.gz | cut -f1))"
