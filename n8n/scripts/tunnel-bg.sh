#!/usr/bin/env bash
# Background n8n tunnel in a tmux session: `make -C n8n tunnel` (kubectl port-forward on 127.0.0.1) under a
# supervisor loop that restarts it when the port-forward exits (e.g. after `llm-connect` restarts the n8n pod).
#   tunnel-bg.sh start     start, or restart if the session exists but n8n doesn't answer; no-op if healthy
#   tunnel-bg.sh status    session, port and HTTPS health (verifies the n8n CA; never skips TLS checks)
#   tunnel-bg.sh logs      last TAIL lines (default 50) of the log; FOLLOW=1 follows it
#   tunnel-bg.sh stop      kill the session
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CLUSTER="${CLUSTER:-kind}"
PORT="${PORT:-8443}"
SESSION="${SESSION:-n8n-tunnel}"
STATE_DIR="$ROOT_DIR/.state"
LOG="$STATE_DIR/n8n-tunnel.log"
CA_FILE="$ROOT_DIR/n8n/.state/$CLUSTER/ca.crt"

need_tmux() {
  command -v tmux >/dev/null && return
  echo "tmux not found. Rebuild the devcontainer (Dev Containers: Rebuild Container), or for now: sudo apt-get install -y tmux"
  echo "Foreground alternative: make -C n8n tunnel"
  exit 1
}

session_up() { tmux has-session -t "=$SESSION" 2>/dev/null; }

# 0 when n8n answers /healthz over verified TLS (cert SANs include 127.0.0.1); port-open check if no CA yet.
healthy() {
  if [ -s "$CA_FILE" ]; then
    curl -sS --fail --max-time 5 --cacert "$CA_FILE" "https://127.0.0.1:$PORT/healthz" >/dev/null 2>&1
  else
    nc -z -w 2 127.0.0.1 "$PORT" 2>/dev/null
  fi
}

start() {
  need_tmux
  if session_up; then
    if healthy; then echo "n8n tunnel already running (tmux session '$SESSION', 127.0.0.1:$PORT)."; return; fi
    echo "tmux session '$SESSION' exists but n8n doesn't answer on 127.0.0.1:$PORT: restarting it."
    tmux kill-session -t "=$SESSION"
  fi
  mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"
  (umask 077; : > "$LOG")
  local loop
  loop="cd $(printf %q "$ROOT_DIR") && export CLUSTER=$(printf %q "$CLUSTER") PORT=$(printf %q "$PORT"); \
while true; do echo \"[\$(date '+%F %T')] starting port-forward\"; make --no-print-directory -C n8n tunnel 2>&1; rc=\$?; \
echo \"[\$(date '+%F %T')] port-forward exited (\$rc), restarting in 3s\"; sleep 3; done >> $(printf %q "$LOG") 2>&1"
  tmux new-session -d -s "$SESSION" "bash -c $(printf %q "$loop")"
  echo -n "Started n8n tunnel in tmux session '$SESSION'; waiting for n8n"
  for _ in $(seq 30); do healthy && { echo " ok."; status; return; }; echo -n .; sleep 1; done
  echo; echo "n8n is not answering yet. Check: make n8n-tunnel-logs"; exit 1
}

status() {
  need_tmux
  local rc=0
  if session_up; then echo "  Session   tmux '$SESSION' running   (attach: tmux attach -t $SESSION, detach: Ctrl+B D)"
  else echo "  Session   not running   (start: make n8n-tunnel)"; rc=1; fi
  if nc -z -w 2 127.0.0.1 "$PORT" 2>/dev/null; then echo "  Port      127.0.0.1:$PORT listening"
  else echo "  Port      127.0.0.1:$PORT closed"; rc=1; fi
  if [ ! -s "$CA_FILE" ]; then echo "  Health    unknown (no CA at ${CA_FILE#"$ROOT_DIR"/}; run make -C n8n ca)"
  elif healthy; then echo "  Health    https://127.0.0.1:$PORT/healthz OK (CA verified)"
  else echo "  Health    n8n not answering over HTTPS"; rc=1; fi
  echo "  Log       ${LOG#"$ROOT_DIR"/}   (make n8n-tunnel-logs)"
  return $rc
}

logs() {
  [ -f "$LOG" ] || { echo "No tunnel log yet (${LOG#"$ROOT_DIR"/}). Start it: make n8n-tunnel"; exit 1; }
  if [ -n "${FOLLOW:-}" ]; then tail -n "${TAIL:-50}" -f "$LOG"; else tail -n "${TAIL:-50}" "$LOG"; fi
}

stop() {
  need_tmux
  if session_up; then tmux kill-session -t "=$SESSION" && echo "Stopped n8n tunnel (tmux session '$SESSION')."
  else echo "n8n tunnel not running."; fi
}

case "${1:-}" in
  start|status|logs|stop) "$1" ;;
  *) echo "usage: $0 start|status|logs|stop" >&2; exit 2 ;;
esac
