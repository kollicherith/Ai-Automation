#!/usr/bin/env bash
# Phase 2 - base system. Run on the VM as the 'ubuntu' user.
#   bash bootstrap.sh            # public mode: opens 80/443 on the instance firewall
#   bash bootstrap.sh --tailscale # skips the firewall rules entirely
# Idempotent: safe to re-run.
set -euo pipefail

TAILSCALE=0
[[ "${1:-}" == "--tailscale" ]] && TAILSCALE=1

say() { printf '\n== %s\n' "$1"; }

say "Updating packages"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

say "Swap"
if swapon --show | grep -q '/swapfile'; then
  echo "swap already active, skipping"
else
  sudo fallocate -l 4G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  grep -qF '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi
free -h

if [[ $TAILSCALE -eq 1 ]]; then
  say "Tailscale mode - skipping instance firewall rules"
  echo "Remember: do NOT add the 80/443 ingress rules in the OCI Console either."
  echo "See references/troubleshooting.md section 4 for the Tailscale steps."
else
  say "Instance firewall (layer 2 of 2)"
  echo "Layer 1 is the OCI Console Security List - this script CANNOT do that part."
  echo "Networking > Virtual Cloud Networks > your VCN > Subnet > Security List"
  echo "  Ingress: 0.0.0.0/0 TCP 80, and 0.0.0.0/0 TCP 443"
  echo

  # Ubuntu on OCI ships a catch-all REJECT in INPUT. An ACCEPT rule appended
  # below it never matches, which is the classic "site silently never loads".
  # Insert above the first REJECT/DROP rather than at a hardcoded position.
  insert_at=$(sudo iptables -L INPUT -n --line-numbers \
    | awk '$2=="REJECT" || $2=="DROP" {print $1; exit}')
  : "${insert_at:=1}"

  for port in 80 443; do
    if sudo iptables -C INPUT -m state --state NEW -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
      echo "port $port ACCEPT already present"
    else
      sudo iptables -I INPUT "$insert_at" -m state --state NEW -p tcp --dport "$port" -j ACCEPT
      echo "port $port ACCEPT inserted at position $insert_at"
    fi
  done

  sudo netfilter-persistent save   # a rule that is not saved vanishes on reboot
  sudo iptables -L INPUT -n --line-numbers | head -20
fi

say "Docker"
if command -v docker >/dev/null 2>&1; then
  echo "docker already installed"
else
  curl -fsSL https://get.docker.com | sudo sh
fi
sudo usermod -aG docker "$USER"
docker --version
sudo docker compose version

say "Done"
echo "Log out and back in (or run 'newgrp docker') so docker works without sudo."
echo "Next: scripts/duckdns-setup.sh"
