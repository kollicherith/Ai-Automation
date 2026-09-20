#!/usr/bin/env bash
# Point git at the repo's tracked hooks. Run once per clone - hooks are not
# copied by git clone, so each machine needs this.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
git config core.hooksPath .githooks
chmod +x .githooks/*
echo "hooks installed: $(git config core.hooksPath)"
echo "Test it with:  echo 'N8N_ENCRYPTION_KEY=$(printf 'a%.0s' {1..64})' > /tmp/x.env && git add -f /tmp/x.env"
