#!/usr/bin/env bash
# Security hardening for the VM. Run after bootstrap.sh, before or after deploy.
#   bash harden.sh              # public mode
#   bash harden.sh --tailscale  # also offers to close SSH to the internet
# Idempotent. Every change it makes is printed; nothing is silent.
set -euo pipefail

TAILSCALE=0
[[ "${1:-}" == "--tailscale" ]] && TAILSCALE=1
say() { printf '\n== %s\n' "$1"; }

say "Automatic security updates"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades
# Security pockets only, and no automatic reboots - a reboot without you
# watching is how an always-on box quietly stops being always-on.
sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
CONF
sudo tee /etc/apt/apt.conf.d/52unattended-upgrades-local >/dev/null <<'CONF'
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
CONF
echo "security updates apply automatically; reboots stay manual"

say "SSH daemon"
# Oracle's Ubuntu image already disables password auth. Assert it rather than
# assume it, and drop root login and agent/TCP forwarding.
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf >/dev/null <<'CONF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitEmptyPasswords no
X11Forwarding no
AllowAgentForwarding no
MaxAuthTries 3
LoginGraceTime 30
CONF
if sudo sshd -t; then
  sudo systemctl reload ssh 2>/dev/null || sudo systemctl reload sshd
  echo "sshd config valid and reloaded"
else
  echo "sshd config INVALID - reverting, nothing changed" >&2
  sudo rm -f /etc/ssh/sshd_config.d/99-hardening.conf
  exit 1
fi

say "fail2ban (SSH brute-force)"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban
sudo tee /etc/fail2ban/jail.d/sshd.local >/dev/null <<'CONF'
[sshd]
enabled = true
maxretry = 4
findtime = 10m
bantime = 1h
CONF
sudo systemctl enable --now fail2ban
sudo fail2ban-client status sshd 2>/dev/null | head -5 || true

say "Docker daemon log caps"
# Belt and braces alongside the per-service logging in docker-compose.yml.
sudo mkdir -p /etc/docker
if [[ -f /etc/docker/daemon.json ]] && ! grep -q log-opts /etc/docker/daemon.json; then
  echo "/etc/docker/daemon.json exists and is not ours - leaving it alone."
  echo "Add log-driver/log-opts by hand if you want daemon-wide caps."
else
  sudo tee /etc/docker/daemon.json >/dev/null <<'CONF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true
}
CONF
  sudo systemctl restart docker
  echo "daemon log caps applied"
fi

say "Backup encryption key"
# Backups contain DECRYPTED credentials and N8N_ENCRYPTION_KEY. They only leave
# this machine safely if they are encrypted before they leave it.
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y age
KEYDIR="$HOME/.config/n8n-backup"
mkdir -p "$KEYDIR"; chmod 700 "$KEYDIR"
if [[ -f "$KEYDIR/identity.txt" ]]; then
  echo "backup keypair already exists, keeping it"
else
  age-keygen -o "$KEYDIR/identity.txt" 2>/dev/null
  chmod 600 "$KEYDIR/identity.txt"
  grep '^# public key: ' "$KEYDIR/identity.txt" | sed 's/^# public key: //' > "$KEYDIR/recipient.txt"
  cat <<MSG

  A backup keypair was generated. The PRIVATE key below is the only thing that
  can decrypt your backups. It lives on this VM - which is the machine the
  backups exist to survive the loss of.

  COPY THIS INTO YOUR PASSWORD MANAGER NOW:

$(sed 's/^/    /' "$KEYDIR/identity.txt")

  Without it, an off-VM backup is an encrypted file nobody can open.
MSG
fi

if [[ $TAILSCALE -eq 1 ]]; then
  say "SSH exposure"
  cat <<'MSG'
  You are on Tailscale, so SSH does not need to be open to the internet at all.
  Oracle's default security list allows TCP 22 from 0.0.0.0/0 - that is the one
  port still exposed on this build, and it is the one people actually attack.

  To close it (do this only once you have CONFIRMED tailscale SSH works):

    1. From another device on your tailnet:  ssh ubuntu@<machine>.<tailnet>.ts.net
    2. Only if that succeeds: OCI Console > Networking > VCN > Subnet >
       Security List > delete the 0.0.0.0/0 TCP 22 ingress rule.

  Do not do step 2 first. Losing SSH before the tailnet route works means
  rebuilding the instance - the console serial connection is the only way back
  and it is painful.
MSG
fi

say "Done"
echo "Review: docs/security.md explains what this does and does not cover."
