#!/usr/bin/env bash
# Usage: test.sh <vm|docker|kind> <ns> <release> <host> <ca-file> <test-port> <vm-dir>
#   vm:     connects to <host>:443 directly (public FQDN, NSG allows the operator IP)
#   docker|kind: opens a temporary port-forward to Traefik and connects to 127.0.0.1:<test-port>
set -uo pipefail
CLUSTER=$1 NS=$2 REL=$3 HOST=$4 CA=$5 TPORT=$6 VM_DIR=$7
STATE=$(dirname "$CA")
fail=0
pass() { echo "PASS  $*"; }
bad()  { echo "FAIL  $*"; fail=1; }

if [ "$CLUSTER" != vm ]; then
  kubectl -n ingress port-forward --address 127.0.0.1 svc/traefik "$TPORT:443" >"$STATE/pf-test.log" 2>&1 &
  pf=$!; trap 'kill $pf 2>/dev/null || true' EXIT
  for _ in $(seq 30); do grep -q Forwarding "$STATE/pf-test.log" && break; sleep 0.5; done
  PORT=$TPORT ADDR=127.0.0.1
else
  PORT=443 ADDR=$HOST
fi
url="https://$HOST:$PORT/"
c() { curl -fsS --max-time 10 --tlsv1.2 --cacert "$CA" --resolve "$HOST:$PORT:$(
  [ "$ADDR" = 127.0.0.1 ] && echo 127.0.0.1 || dig +short "$HOST" | tail -1)" "$@"; }

pods=$(kubectl -n "$NS" get pods -l "app.kubernetes.io/instance=$REL" --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}')
echo "Cluster: $CLUSTER   Pods: $pods"
seen=""
for _ in $(seq 12); do
  body=$(c "$url") || { bad "HTTPS request ($url)"; exit 1; }
  p=$(sed -n 's|.*<h1 id="pod">\([^<]*\)</h1>.*|\1|p' <<<"$body")
  [[ " $pods " == *" $p "* ]] || bad "page shows '$p', not a running pod"
  [[ " $seen " == *" $p "* ]] || seen="$seen $p"
done
pass "HTTPS with certificate verified against the exported CA"
pass "homepage shows pod name; pods seen over 12 requests:$seen"

out=$(openssl s_client -connect "$ADDR:$PORT" -servername "$HOST" -tls1_1 -cipher 'DEFAULT:@SECLEVEL=0' </dev/null 2>&1 || true)
if grep -q 'alert protocol version' <<<"$out"; then pass "TLS 1.1 rejected by server"
elif grep -qE 'Cipher is [A-Z0-9]' <<<"$out" && ! grep -q 'Cipher is (NONE)' <<<"$out"; then bad "TLS 1.1 accepted"
else echo "SKIP  TLS 1.1 probe inconclusive (local openssl cannot offer TLS 1.1)"; fi

if [ "$CLUSTER" = vm ]; then
  # Negative TCP probe only (no HTTP request is sent): port 80 must not accept connections.
  if nc -z -G 5 -w 5 "$HOST" 80 2>/dev/null; then bad "port 80 reachable"; else pass "port 80 closed"; fi
else
  ext=$(kubectl -n ingress get svc -o jsonpath='{range .items[?(@.spec.type!="ClusterIP")]}{.metadata.name} {end}')
  [ -z "$ext" ] && pass "Traefik not published on the Mac (ClusterIP only)" || bad "Traefik service published: $ext"
fi

echo; echo "URL: https://$HOST$([ "$CLUSTER" != vm ] && echo ":<PORT> (make tunnel CLUSTER=$CLUSTER)")/"
exit $fail
