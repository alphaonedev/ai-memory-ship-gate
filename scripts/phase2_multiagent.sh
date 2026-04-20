#!/usr/bin/env bash
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
#
# Phase 2 — multi-agent / multi-node federation under --quorum-writes.
# Run from the chaos-client droplet. Requires the three peer node IPs
# via environment variables: NODE_A_IP, NODE_B_IP, NODE_C_IP.
#
# Usage:
#   NODE_A_IP=... NODE_B_IP=... NODE_C_IP=... ./phase2_multiagent.sh
#
# Produces /tmp/phase2.json on stdout.

set -euo pipefail

: "${NODE_A_IP:?}"
: "${NODE_B_IP:?}"
: "${NODE_C_IP:?}"
: "${NODE_A_PRIV:?}"
: "${NODE_B_PRIV:?}"
: "${NODE_C_PRIV:?}"

AGENTS=(ai:agent-alice ai:agent-bob ai:agent-charlie ai:agent-dana)
WRITES_PER_AGENT=50
NS=ship-gate-phase2

log() { printf '[phase2] %s\n' "$*" >&2; }

# ---- Reconfigure serve on each peer with --quorum-writes 2 ----
# SSH uses PUBLIC IPs (control plane); federation/quorum uses PRIVATE
# IPs (VPC-only firewall allow rule on 9077). Writing from chaos also
# uses the PRIVATE IP of node-a so the source IP at node-a matches the
# chaos_client.ipv4_address_private that the firewall permits.
for role in a:"$NODE_A_IP":"$NODE_A_PRIV" \
            b:"$NODE_B_IP":"$NODE_B_PRIV" \
            c:"$NODE_C_IP":"$NODE_C_PRIV"; do
  key=${role%%:*}; rest=${role#*:}; pub=${rest%:*}; self_priv=${rest#*:}
  log "reconfigure serve on node-$key ($pub, private $self_priv)"
  # Pass the node's own private IP explicitly so the remote script
  # builds the peer list without including itself. Run 9 showed
  # `hostname -I | awk '{print $1}'` returns the PUBLIC IP on DO
  # droplets (eth0 is public); that produced a peer list containing
  # the local private IP → quorum writes looped to self → all writes
  # failed with quorum_not_met.
  ssh -o StrictHostKeyChecking=no root@"$pub" bash -s -- \
    "$NODE_A_PRIV" "$NODE_B_PRIV" "$NODE_C_PRIV" "$self_priv" <<'REMOTE'
set -e
A="$1"; B="$2"; C="$3"; SELF="$4"
PEERS=""
[ "$SELF" != "$A" ] && PEERS="http://$A:9077"
[ "$SELF" != "$B" ] && PEERS="${PEERS:+$PEERS,}http://$B:9077"
[ "$SELF" != "$C" ] && PEERS="${PEERS:+$PEERS,}http://$C:9077"
pkill -f 'ai-memory serve' 2>/dev/null || true
sleep 1
nohup ai-memory serve \
  --host 0.0.0.0 --port 9077 \
  --quorum-writes 2 \
  --quorum-peers "$PEERS" \
  --quorum-timeout-ms 3000 \
  > /var/log/ai-memory-serve.log 2>&1 &
# Poll health up to 30s — nohup + DB init can take a few seconds,
# and a fixed `sleep 2` loses the race on slower droplets.
for attempt in $(seq 1 30); do
  if curl -sSf http://127.0.0.1:9077/api/v1/health 2>/dev/null | grep -q '"ok"'; then
    break
  fi
  sleep 1
done
# Final health assertion — fail loud if never came up.
curl -sSf http://127.0.0.1:9077/api/v1/health | grep -q '"ok"'
REMOTE
done

# ---- Multi-agent write burst -----------------------------------
# All curls go to private IPs; chaos's private IP is the source and
# is in the firewall allow-list.
log "write burst: 4 agents × 50 writes"
# Subshell-safe counters: each backgrounded agent appends its per-write
# status code to a tmpfile; the parent tallies after `wait`.
CODES_FILE=$(mktemp)
# Log ONE sample write's response body so we can debug when counts are 0.
SAMPLE_FILE=$(mktemp)
for AGENT in "${AGENTS[@]}"; do
  for i in $(seq 1 "$WRITES_PER_AGENT"); do
    CODE=$(curl -sS -o /tmp/resp-$AGENT-$i.json -w '%{http_code}' \
      -H "X-Agent-Id: $AGENT" \
      -H "Content-Type: application/json" \
      -X POST "http://$NODE_A_PRIV:9077/api/v1/memories" \
      -d "{\"tier\":\"mid\",\"namespace\":\"$NS\",\"title\":\"$AGENT-w$i\",\"content\":\"multi-agent write $AGENT seq $i\",\"priority\":5,\"confidence\":1.0,\"source\":\"api\",\"metadata\":{}}" \
      2>/dev/null || echo 000)
    echo "$CODE" >> "$CODES_FILE"
    # Capture first write's response body for diagnosis.
    if [ "$AGENT" = "ai:agent-alice" ] && [ "$i" = "1" ]; then
      cp "/tmp/resp-$AGENT-$i.json" "$SAMPLE_FILE" 2>/dev/null || true
    fi
  done &
done
wait

# `grep -c` returns exit 1 with "0" on stdout when no match; use
# `awk` so we always get a clean count regardless of match presence.
OK=$(awk '/^201$/{n++} END{print n+0}' "$CODES_FILE")
QNM=$(awk '/^503$/{n++} END{print n+0}' "$CODES_FILE")
TOTAL=$(wc -l < "$CODES_FILE")
FAIL=$((TOTAL - OK - QNM))
log "burst totals: OK=$OK  QNM=$QNM  FAIL=$FAIL (total=$TOTAL)"
log "code distribution:"
sort "$CODES_FILE" | uniq -c | while read -r cnt code; do
  log "  $code: $cnt"
done
if [ -s "$SAMPLE_FILE" ]; then
  log "sample response body (first write):"
  head -c 500 "$SAMPLE_FILE" | sed 's/^/  /' >&2
  echo >&2
else
  log "sample response body: (empty — no response captured)"
fi

# ---- Settle period ---------------------------------------------
# Run 13 showed 30s leaves node-C at 73% and node-B at 89.5% — below
# the 95% threshold. 90s = 9 sync-daemon cycles at the default 10s
# cadence, which comfortably covers pulling 200 records on a fresh
# peer. If convergence still lags after 90s, that's an ai-memory-mcp
# sync-daemon performance issue (file separately) — don't just keep
# bumping this.
SETTLE_SECS="${SETTLE_SECS:-90}"
log "settle ${SETTLE_SECS}s for sync-daemon convergence"
sleep "$SETTLE_SECS"

# ---- Convergence check -----------------------------------------
# Also pull total stats + namespace list for diagnosis when namespace
# filter returns 0 unexpectedly.
declare -A COUNTS
for role in A:"$NODE_A_PRIV" B:"$NODE_B_PRIV" C:"$NODE_C_PRIV"; do
  key=${role%%:*}; ip=${role##*:}
  n=$(curl -sS "http://$ip:9077/api/v1/memories?namespace=$NS&limit=1000" \
      | jq '.memories | length' 2>/dev/null || echo 0)
  COUNTS[$key]=$n
  total=$(curl -sS "http://$ip:9077/api/v1/stats" 2>/dev/null | jq '.total' 2>/dev/null || echo "?")
  ns_list=$(curl -sS "http://$ip:9077/api/v1/namespaces" 2>/dev/null | jq -c '.' 2>/dev/null || echo "?")
  log "node-$key count(ns=$NS)=$n  stats.total=$total  namespaces=$ns_list"
done

# ---- Quorum-not-met probe --------------------------------------
# SSH (control plane) still uses public IPs; curl writes use private.
# Run 13: pkill killed ai-memory serve successfully but ssh itself
# returned 255 (transport close after remote process tree went down),
# which with `set -e` aborted the script before probe1/probe2 ran.
# `|| true` INSIDE the remote quotes only protects the remote exit
# code; we need an outer `|| true` to absorb transport-level 255s.
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=5"
log "probe: kill node-b, confirm node-a still meets quorum via node-c"
ssh $SSH_OPTS root@"$NODE_B_IP" "pkill -f 'ai-memory serve' || true" || true
sleep 2
PROBE1=$(curl -sS -o /dev/null -w '%{http_code}' \
  -H "X-Agent-Id: ai:probe" -H "Content-Type: application/json" \
  -X POST "http://$NODE_A_PRIV:9077/api/v1/memories" \
  -d "{\"tier\":\"mid\",\"namespace\":\"$NS-probe1\",\"title\":\"probe1-$(date +%s)\",\"content\":\"single-peer-down probe\",\"priority\":5,\"confidence\":1.0,\"source\":\"api\",\"metadata\":{}}" \
  2>/dev/null || echo 000)

log "probe: kill node-c too, confirm node-a fails with 503 quorum_not_met"
ssh $SSH_OPTS root@"$NODE_C_IP" "pkill -f 'ai-memory serve' || true" || true
sleep 2
PROBE2=$(curl -sS -o /dev/null -w '%{http_code}' \
  -H "X-Agent-Id: ai:probe" -H "Content-Type: application/json" \
  -X POST "http://$NODE_A_PRIV:9077/api/v1/memories" \
  -d "{\"tier\":\"mid\",\"namespace\":\"$NS-probe2\",\"title\":\"probe2-$(date +%s)\",\"content\":\"both-peers-down probe\",\"priority\":5,\"confidence\":1.0,\"source\":\"api\",\"metadata\":{}}" \
  2>/dev/null || echo 000)

# ---- Pass/fail --------------------------------------------------
TOTAL_WRITES=$((${#AGENTS[@]} * WRITES_PER_AGENT))
CONVERGENCE_MIN=$(( OK * 95 / 100 ))
PASS=true; REASONS=()

# Each node converges to >= 95% of OK writes.
for k in A B C; do
  n=${COUNTS[$k]}
  (( n >= CONVERGENCE_MIN )) || { PASS=false; REASONS+=("node-$k count $n < 95% of $OK"); }
done

# Probe 1: with one peer down and majority quorum (W=2, N=3), writes
# should still succeed via the remaining peer.
[[ "$PROBE1" == "201" ]] || { PASS=false; REASONS+=("probe1 expected 201, got $PROBE1"); }

# Probe 2: with both peers down, writes must fail with 503.
[[ "$PROBE2" == "503" ]] || { PASS=false; REASONS+=("probe2 expected 503, got $PROBE2"); }

jq -n \
  --arg pass "$PASS" \
  --argjson total "$TOTAL_WRITES" \
  --argjson ok "$OK" \
  --argjson qnm "$QNM" \
  --argjson fail "$FAIL" \
  --argjson node_a "${COUNTS[A]}" \
  --argjson node_b "${COUNTS[B]}" \
  --argjson node_c "${COUNTS[C]}" \
  --arg probe1 "$PROBE1" \
  --arg probe2 "$PROBE2" \
  --argjson reasons "$(printf '%s\n' "${REASONS[@]}" | jq -R . | jq -s .)" \
  '{phase:2, pass:($pass=="true"), total_writes:$total, ok:$ok, quorum_not_met:$qnm, fail:$fail,
    counts:{a:$node_a,b:$node_b,c:$node_c},
    probe1_single_peer_down:$probe1, probe2_both_peers_down:$probe2,
    reasons:$reasons}' | tee /tmp/phase2.json

$PASS || exit 1
