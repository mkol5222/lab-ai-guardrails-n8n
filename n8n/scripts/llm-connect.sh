#!/usr/bin/env bash
# Connect n8n to the in-cluster llmgw gateway:
#   1. copy llmgw's private CA (public cert) into ConfigMap llmgw-ca -> n8n trusts it (NODE_EXTRA_CA_CERTS)
#   2. import/refresh the n8n credential "llmgw (Lakera-guarded)" (OpenAI API type) holding the scoped
#      virtual key from secret llmgw/llmgw-client-n8n (`make -C ../llmgw client-key CLIENT=n8n`)
#   3. import the workflow JSON (default: workflows/llmgw-chat-agent.json)
# The key travels kubectl -> jq -> kubectl exec stdin -> n8n CLI; it is never printed or put on argv,
# and the temporary file inside the pod (mode 600) is deleted right after the import.
# Usage: llm-connect.sh <n8n-ns> <n8n-release> <llmgw-ns> <llmgw-release> <workflow.json>
set -euo pipefail
NS=$1 REL=$2 GW_NS=$3 GW_REL=$4 WF=$5
CRED_ID=LlmgwGuardedKey1
CRED_NAME="llmgw (Lakera-guarded)"
GW_URL="https://$GW_REL.$GW_NS.svc.cluster.local/v1"
KEY_SECRET="$GW_REL-client-n8n"

kubectl -n "$GW_NS" get secret "$GW_REL-tls" >/dev/null 2>&1 || { echo "llmgw not deployed in namespace $GW_NS (make -C ../llmgw up)"; exit 1; }
kubectl -n "$GW_NS" get secret "$KEY_SECRET" >/dev/null 2>&1 || { echo "No n8n client key. Run: make -C ../llmgw client-key CLIENT=n8n"; exit 1; }

# 1. CA (public certificate only)
kubectl -n "$GW_NS" get secret "$GW_REL-tls" -o jsonpath='{.data.ca\.crt}' | base64 -d \
  | kubectl -n "$NS" create configmap llmgw-ca --from-file=ca.crt=/dev/stdin --dry-run=client -o yaml \
  | kubectl apply -f - >/dev/null
echo "CA: ConfigMap $NS/llmgw-ca updated"

# 2. Credential (n8n encrypts it with its N8N_ENCRYPTION_KEY on import)
kubectl -n "$GW_NS" get secret "$KEY_SECRET" -o jsonpath='{.data.api_key}' | base64 -d \
  | jq -Rc --arg id "$CRED_ID" --arg n "$CRED_NAME" --arg u "$GW_URL" \
      '[{id:$id, name:$n, type:"openAiApi", data:{apiKey:., url:$u, header:false}}]' \
  | kubectl -n "$NS" exec -i "deploy/$REL" -c n8n -- sh -c \
      'umask 077; f=$(mktemp); cat > "$f"; n8n import:credentials --input="$f" >/dev/null 2>&1; rc=$?; rm -f "$f"; exit $rc'
echo "Credential: \"$CRED_NAME\" ($CRED_ID) -> $GW_URL"

# 3. Workflow
kubectl -n "$NS" exec -i "deploy/$REL" -c n8n -- sh -c \
  'f=$(mktemp); cat > "$f"; n8n import:workflow --input="$f" >/dev/null 2>&1; rc=$?; rm -f "$f"; exit $rc' < "$WF"
echo "Workflow: imported $(jq -r '"\"\(.name)\" (\(.id))"' "$WF") from $WF"
