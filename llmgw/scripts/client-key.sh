#!/usr/bin/env bash
# Create (or keep) a scoped LiteLLM virtual key for an in-cluster client and store it in a Secret.
#   - allowed models: only the Lakera-blocking model names (no monitor/ or unguarded/ variants)
#   - key_alias = client name, rate limits, no admin rights
# The key goes from the API response straight into `kubectl apply` over pipes: never printed,
# never on argv, never in a file.
# Usage: client-key.sh <ns> <release> <client-name> <local-port> [rpm] [tpm]
set -euo pipefail
NS=$1 REL=$2 CLIENT=$3 PORT=$4 RPM=${5:-30} TPM=${6:-200000}
SECRET="$REL-client-$CLIENT"
STATE=$(mktemp -d); trap 'kill ${pf:-} 2>/dev/null || true; rm -rf "$STATE"' EXIT

kubectl -n "$NS" port-forward --address 127.0.0.1 "svc/$REL" "$PORT:443" >"$STATE/pf.log" 2>&1 & pf=$!
for _ in $(seq 30); do grep -q Forwarding "$STATE/pf.log" && break; sleep 0.5; done
kubectl -n "$NS" get secret "$REL-tls" -o jsonpath='{.data.ca\.crt}' | base64 -d > "$STATE/ca.crt"

MASTER=$(kubectl -n "$NS" get secret "$REL-master-key" -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d)
api() { curl -sS --max-time 30 --tlsv1.2 --cacert "$STATE/ca.crt" --resolve "llmgw.localhost:$PORT:127.0.0.1" \
  -H @<(printf 'Authorization: Bearer %s\nContent-Type: application/json\n' "$MASTER") "$@"; }
BASE="https://llmgw.localhost:$PORT"

# Reuse a stored key if the gateway still knows it.
if kubectl -n "$NS" get secret "$SECRET" >/dev/null 2>&1; then
  code=$(kubectl -n "$NS" get secret "$SECRET" -o jsonpath='{.data.api_key}' | base64 -d \
    | { read -r k; api -o /dev/null -w '%{http_code}' --get --data-urlencode "key=$k" "$BASE/key/info"; })
  if [ "$code" = 200 ]; then echo "Client key for '$CLIENT' exists and is valid (secret $NS/$SECRET)."; exit 0; fi
  echo "Stored key for '$CLIENT' is not valid any more (HTTP $code): issuing a new one."
fi

MODELS=$(helm get values "$REL" -n "$NS" -o json | jq -c '.models // ["openrouter/free"]')
BODY=$(jq -nc --arg a "$CLIENT" --argjson m "$MODELS" --argjson rpm "$RPM" --argjson tpm "$TPM" \
  '{key_alias:$a, models:$m, rpm_limit:$rpm, tpm_limit:$tpm, metadata:{owner:$a, purpose:"in-cluster client, Lakera-guarded models only"}}')
api --data "$BODY" "$BASE/key/generate" > "$STATE/resp.json"
jq -e '.key | startswith("sk-")' "$STATE/resp.json" >/dev/null || { echo "Key generation failed: $(jq -c '.error // .' "$STATE/resp.json" | cut -c1-200)"; exit 1; }

jq -r '"api_key=\(.key)"' "$STATE/resp.json" \
  | kubectl -n "$NS" create secret generic "$SECRET" --from-env-file=/dev/stdin --dry-run=client -o yaml \
  | kubectl label --local -f - "app.kubernetes.io/part-of=$REL" "llmgw/client=$CLIENT" -o yaml \
  | kubectl apply -f - >/dev/null
echo "Issued key for '$CLIENT': $(jq length <<<"$MODELS") guarded models, rpm=$RPM, tpm=$TPM -> secret $NS/$SECRET"
unset MASTER
