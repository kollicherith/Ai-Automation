#!/usr/bin/env bash
# Verify the pre-commit secret hook still blocks what it should, and still lets
# ordinary work through. Runs against a throwaway copy - never touches your repo.
#   bash stack/scripts/test-git-hooks.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
tar cf - --exclude=.git -C "$ROOT" . | (cd "$WORK" && tar xf -)
cd "$WORK"
git init -q .; git config user.email t@t; git config user.name t
git config core.hooksPath .githooks; chmod +x .githooks/*
git add -A && git commit -q -m base --no-verify

pass=0; fail=0
t() {
  eval "$2" >/dev/null 2>&1
  if git commit -q -m test >/dev/null 2>&1; then got=allow; else got=block; fi
  git reset -q --hard HEAD >/dev/null 2>&1; git clean -qfdx >/dev/null 2>&1
  if [[ "$got" == "$3" ]]; then echo "  ok    $1"; pass=$((pass+1))
  else echo "  FAIL  $1 (expected $3, got $got)"; fail=$((fail+1)); fi
}

echo "Must block:"
t "a .env file"           "printf 'X=1\n' > .env && git add -f .env" block
t "a Groq key"            "printf 'gsk_abcdefghij0123456789ABCDEFGHIJ\n' >> README.md && git add README.md" block
t "an sk- API key"        "printf 'sk-proj-abcdefghij0123456789ABCDEFGH\n' >> README.md && git add README.md" block
t "a Google API key"      "printf 'AIzaSyD1234567890abcdefghijklmnopqrstuv\n' >> README.md && git add README.md" block
t "an encryption key"     "printf 'N8N_ENCRYPTION_KEY=%064d\n' 1 >> README.md && git add README.md" block
t "an SSH private key"    "printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\n' > k.txt && git add k.txt" block
t "an age private key"    "printf 'AGE-SECRET-KEY-1QQQQQQQQQQQQQQQQQQQQQQQQ\n' >> README.md && git add README.md" block
t "a backup tarball"      "printf x > n8n-2026-01-01.tar.gz.age && git add -f n8n-2026-01-01.tar.gz.age" block
t "an OCI launch.json"    "printf '{\"a\":1}' > launch.json && git add -f launch.json" block
t "a rendered Caddyfile"  "printf 'x {\n}\n' > stack/Caddyfile && git add -f stack/Caddyfile" block
t "a DuckDNS token"       "printf 'token=1a2b3c4d-5e6f-7a8b-x\n' >> README.md && git add README.md" block

echo "Must allow:"
t "an ordinary doc edit"  "printf '\nA normal sentence.\n' >> README.md && git add README.md" allow
t "a script edit"         "printf '\n# a comment\n' >> stack/scripts/deploy.sh && git add stack/scripts/deploy.sh" allow
t ".env.example"          "printf '\n# note\n' >> stack/.env.example && git add stack/.env.example" allow
t "the credentials guide" "printf '\nMore prose.\n' >> docs/llm-credentials.md && git add docs/llm-credentials.md" allow
t "the Caddyfile template" "printf '\n# note\n' >> stack/Caddyfile.template && git add stack/Caddyfile.template" allow
t "a new script"          "printf '#!/bin/bash\necho hi\n' > stack/scripts/new.sh && git add stack/scripts/new.sh" allow

echo
echo "$pass passed, $fail failed"
exit $fail
