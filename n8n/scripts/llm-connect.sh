#!/usr/bin/env bash
# Connect n8n to the in-cluster llmgw gateway and import lab workflows:
#   1. copy llmgw's private CA (public cert) into ConfigMap llmgw-ca -> n8n trusts it (NODE_EXTRA_CA_CERTS)
#   2. import/refresh the n8n credential "llmgw (Lakera-guarded)" (OpenAI API type) holding the scoped
#      virtual key from secret llmgw/llmgw-client-n8n (`make -C ../llmgw client-key CLIENT=n8n`)
#   3. if secret llmgw/llmgw-provider-keys exists, import/refresh "LakeraAPI" (httpBearerAuth,
#      shared by Prompt Roulette V2 and the Lakera API pre-check workflow) and substitute
#      <YOUR_LAKERA_PROJECT_ID> in-memory on import
#   4. import one or more workflow JSON files
# Keys travel kubectl -> jq -> kubectl exec stdin -> n8n CLI; they are never printed or put on argv,
# and temporary files inside the pod (mode 600) are deleted right after import.
# Usage: llm-connect.sh <n8n-ns> <n8n-release> <llmgw-ns> <llmgw-release> <workflow.json> [workflow2.json ...]
set -euo pipefail
NS=$1 REL=$2 GW_NS=$3 GW_REL=$4
shift 4
CRED_ID=LlmgwGuardedKey1
CRED_NAME="llmgw (Lakera-guarded)"
LAKERA_CRED_ID=dwOBu8Lap8nw2gG9
LAKERA_CRED_NAME="LakeraAPI"
GW_URL="https://$GW_REL.$GW_NS.svc.cluster.local/v1"
KEY_SECRET="$GW_REL-client-n8n"
PROVIDER_SECRET="$GW_REL-provider-keys"

kubectl -n "$GW_NS" get secret "$GW_REL-tls" >/dev/null 2>&1 || { echo "llmgw not deployed in namespace $GW_NS (make -C ../llmgw up)"; exit 1; }
kubectl -n "$GW_NS" get secret "$KEY_SECRET" >/dev/null 2>&1 || { echo "No n8n client key. Run: make -C ../llmgw client-key CLIENT=n8n"; exit 1; }

# 1. CA (public certificate only)
kubectl -n "$GW_NS" get secret "$GW_REL-tls" -o jsonpath='{.data.ca\.crt}' | base64 -d \
  | kubectl -n "$NS" create configmap llmgw-ca --from-file=ca.crt=/dev/stdin --dry-run=client -o yaml \
  | kubectl apply -f - >/dev/null
echo "CA: ConfigMap $NS/llmgw-ca updated"

# 2. llmgw OpenAI API credential (n8n encrypts it with its N8N_ENCRYPTION_KEY on import)
kubectl -n "$GW_NS" get secret "$KEY_SECRET" -o jsonpath='{.data.api_key}' | base64 -d \
  | jq -Rc --arg id "$CRED_ID" --arg n "$CRED_NAME" --arg u "$GW_URL" \
      '[{id:$id, name:$n, type:"openAiApi", data:{apiKey:., url:$u, header:false}}]' \
  | kubectl -n "$NS" exec -i "deploy/$REL" -c n8n -- sh -c \
      'umask 077; f=$(mktemp); cat > "$f"; n8n import:credentials --input="$f" >/dev/null 2>&1; rc=$?; rm -f "$f"; exit $rc'
echo "Credential: \"$CRED_NAME\" ($CRED_ID) -> $GW_URL"

# 3. Lakera Guard API Bearer Auth credential + project ID (for the pre-check workflow)
LAKERA_PID=""
if kubectl -n "$GW_NS" get secret "$PROVIDER_SECRET" >/dev/null 2>&1; then
  kubectl -n "$GW_NS" get secret "$PROVIDER_SECRET" -o jsonpath='{.data.LAKERA_API_KEY}' | base64 -d \
    | jq -Rc --arg id "$LAKERA_CRED_ID" --arg n "$LAKERA_CRED_NAME" \
        '[{id:$id, name:$n, type:"httpBearerAuth", data:{token:.}}]' \
    | kubectl -n "$NS" exec -i "deploy/$REL" -c n8n -- sh -c \
        'umask 077; f=$(mktemp); cat > "$f"; n8n import:credentials --input="$f" >/dev/null 2>&1; rc=$?; rm -f "$f"; exit $rc'
  echo "Credential: \"$LAKERA_CRED_NAME\" ($LAKERA_CRED_ID) -> https://api.lakera.ai/v2/guard"
  LAKERA_PID=$(kubectl -n "$GW_NS" get secret "$PROVIDER_SECRET" -o jsonpath='{.data.LAKERA_PROJECT_ID}' | base64 -d)
fi

# 4. Workflows (substitute <YOUR_LAKERA_PROJECT_ID> in-memory if available; never modifies the repo file)
for wf in "$@"; do
  if [ -n "$LAKERA_PID" ]; then
    jq --arg pid "$LAKERA_PID" \
      '(.nodes[]? | select(.name == "Lakera Guard Config") | .parameters.assignments.assignments[]? | select(.name == "lakera_project_id" and .value == "<YOUR_LAKERA_PROJECT_ID>") | .value) = $pid' \
      "$wf"
  else
    cat "$wf"
  fi | kubectl -n "$NS" exec -i "deploy/$REL" -c n8n -- sh -c \
    'f=$(mktemp); cat > "$f"; n8n import:workflow --input="$f" >/dev/null 2>&1; rc=$?; rm -f "$f"; exit $rc'
  echo "Workflow: imported $(jq -r '"\"\(.name)\" (\(.id))"' "$wf") from $wf"
done
