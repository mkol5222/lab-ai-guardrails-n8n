#!/usr/bin/env bash
# Import one or more local workflow JSON files into the running n8n pod (idempotent by workflow id).
# Usage: import-workflows.sh <n8n-ns> <n8n-release> <workflow.json> [workflow2.json ...]
set -euo pipefail
NS=$1 REL=$2
shift 2
[ "$#" -gt 0 ] || { echo "Usage: $0 <namespace> <release> <workflow.json> [...]"; exit 1; }

for WF in "$@"; do
  [ -f "$WF" ] || { echo "Workflow file not found: $WF"; exit 1; }
  kubectl -n "$NS" exec -i "deploy/$REL" -c n8n -- sh -c \
    'f=$(mktemp); cat > "$f"; n8n import:workflow --input="$f" >/dev/null 2>&1; rc=$?; rm -f "$f"; exit $rc' < "$WF"
  echo "Workflow: imported $(jq -r '"\"\(.name)\" (\(.id))"' "$WF") from $WF"
done
