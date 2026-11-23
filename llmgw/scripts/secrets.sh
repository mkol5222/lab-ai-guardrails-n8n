#!/usr/bin/env bash
# Prompt for the OpenRouter + Lakera credentials and store them in a Kubernetes Secret.
# Values are read with hidden input, never echoed, never put on a command line (argv) or in a file:
# they go from shell builtins (printf) over pipes straight into `kubectl apply`.
# Usage: secrets.sh <namespace> <secret-name> [deployment-to-restart]
set -euo pipefail
NS=$1 NAME=$2 DEPLOY=${3:-}

[ -t 0 ] || { echo "make secrets needs an interactive terminal (in Claude Code: type  ! make -C llmgw secrets)"; exit 1; }

read -rsp "OpenRouter API key (hidden): " OR_KEY; echo
read -rsp "Lakera Guard API key (hidden): " LK_KEY; echo
read -rp  "Lakera project ID (e.g. project-1234567890): " LK_PROJECT
for v in OR_KEY LK_KEY LK_PROJECT; do [ -n "${!v}" ] || { echo "$v is empty, aborting."; exit 1; }; done
[[ $LK_PROJECT =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Project ID contains unexpected characters, aborting."; exit 1; }

echo "Checking OpenRouter key..."
code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 \
  -H @<(printf 'Authorization: Bearer %s\n' "$OR_KEY") https://openrouter.ai/api/v1/key) || code=000
[ "$code" = 200 ] || { echo "OpenRouter rejected the key (HTTP $code), aborting."; exit 1; }

echo "Checking Lakera key + project (synthetic text)..."
code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 \
  -H @<(printf 'Authorization: Bearer %s\nContent-Type: application/json\n' "$LK_KEY") \
  --data @<(printf '{"messages":[{"role":"user","content":"Hello, this is a connectivity check."}],"project_id":"%s"}' "$LK_PROJECT") \
  https://api.lakera.ai/v2/guard) || code=000
[ "$code" = 200 ] || { echo "Lakera rejected the key or project (HTTP $code), aborting."; exit 1; }

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
printf 'OPENROUTER_API_KEY=%s\nLAKERA_API_KEY=%s\nLAKERA_PROJECT_ID=%s\n' "$OR_KEY" "$LK_KEY" "$LK_PROJECT" \
  | kubectl -n "$NS" create secret generic "$NAME" --from-env-file=/dev/stdin --dry-run=client -o yaml \
  | kubectl apply -f - >/dev/null
kubectl -n "$NS" label secret "$NAME" app.kubernetes.io/part-of=llmgw --overwrite >/dev/null
unset OR_KEY LK_KEY
echo "Stored secret $NS/$NAME (OPENROUTER_API_KEY, LAKERA_API_KEY, LAKERA_PROJECT_ID)."

if [ -n "$DEPLOY" ] && kubectl -n "$NS" get deploy "$DEPLOY" >/dev/null 2>&1; then
  kubectl -n "$NS" rollout restart deploy/"$DEPLOY" >/dev/null && echo "Restarted $DEPLOY to load the new keys."
fi
