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
for role in a:"$NODE_A_IP" b:"$NODE_B_IP" c:"$NODE_C_IP"; do
  key=${role%%:*}; ip=${role##*:}
  log "reconfigure serve on node-$key ($ip)"
  ssh -o StrictHostKeyChecking=no root@"$ip" bash -s -- \
    "$NODE_A_PRIV" "$NODE_B_PRIV" "$NODE_C_PRIV" <<'REMOTE'
set -e
A="$1"; B="$2"; C="$3"
# Identify which private IP this host owns so we skip it in the peer list.
HOST_IP=$(hostname -I | awk '{print $1}')
PEERS=""
[ "$HOST_IP" != "$A" ] && PEERS="http://$A:9077"
[ "$HOST_IP" != "$B" ] && PEERS="${PEERS:+$PEERS,}http://$B:9077"
[ "$HOST_IP" != "$C" ] && PEERS="${PEERS:+$PEERS,}http://$C:9077"
pkill -f 'ai-memory serve' 2>/dev/null || true
sleep 1
nohup ai-memory serve \
  --host 0.0.0.0 --port 9077 \
  --quorum-writes 2 \
  --quorum-peers "$PEERS" \
  --quorum-timeout-ms 3000 \
  > /var/log/ai-memory-serve.log 2>&1 &
sleep 2
curl -sSf http://127.0.0.1:9077/api/v1/health | grep -q '"ok"'
REMOTE
done

# ---- Multi-agent write burst -----------------------------------
# All curls go to private IPs; chaos's private IP is the source and
# is in the firewall allow-list.
log "write burst: 4 agents × 50 writes"
OK=0; FAIL=0; QNM=0
for AGENT in "${AGENTS[@]}"; do
  for i in $(seq 1 "$WRITES_PER_AGENT"); do
    CODE=$(curl -sS -o /tmp/resp.json -w '%{http_code}' \
      -H "X-Agent-Id: $AGENT" \
      -H "Content-Type: application/json" \
      -X POST "http://$NODE_A_PRIV:9077/api/v1/memories" \
      -d "{\"tier\":\"mid\",\"namespace\":\"$NS\",\"title\":\"$AGENT-w$i\",\"content\":\"multi-agent write $AGENT seq $i\",\"priority\":5,\"confidence\":1.0,\"source\":\"ship-gate\",\"metadata\":{}}" \
      2>/dev/null || echo 000)
    case "$CODE" in
      201) OK=$((OK+1));;
      503) QNM=$((QNM+1));;
      *)   FAIL=$((FAIL+1));;
    esac
  done &
done
wait

# ---- Settle period ---------------------------------------------
# 30s is three sync-daemon cycles at default 10s cadence — enough
# for the quorum-ack + downstream-replicate chain to converge on the
# default happy path. If the 95%-convergence check fails, bump to 60s
# via SETTLE_SECS override before assuming a regression.
SETTLE_SECS="${SETTLE_SECS:-30}"
log "settle ${SETTLE_SECS}s for sync-daemon convergence"
sleep "$SETTLE_SECS"

# ---- Convergence check -----------------------------------------
declare -A COUNTS
for role in A:"$NODE_A_PRIV" B:"$NODE_B_PRIV" C:"$NODE_C_PRIV"; do
  key=${role%%:*}; ip=${role##*:}
  n=$(curl -sS "http://$ip:9077/api/v1/memories?namespace=$NS&limit=1000" \
      | jq '.memories | length' 2>/dev/null || echo 0)
  COUNTS[$key]=$n
  log "node-$key count: $n"
done

# ---- Quorum-not-met probe --------------------------------------
# SSH (control plane) still uses public IPs; curl writes use private.
log "probe: kill node-b, confirm node-a still meets quorum via node-c"
ssh -o StrictHostKeyChecking=no root@"$NODE_B_IP" "pkill -f 'ai-memory serve' || true"
sleep 2
PROBE1=$(curl -sS -o /dev/null -w '%{http_code}' \
  -H "X-Agent-Id: ai:probe" -H "Content-Type: application/json" \
  -X POST "http://$NODE_A_PRIV:9077/api/v1/memories" \
  -d "{\"tier\":\"mid\",\"namespace\":\"$NS-probe1\",\"title\":\"probe1-$(date +%s)\",\"content\":\"single-peer-down probe\",\"priority\":5,\"confidence\":1.0,\"source\":\"probe\",\"metadata\":{}}" \
  2>/dev/null || echo 000)

log "probe: kill node-c too, confirm node-a fails with 503 quorum_not_met"
ssh -o StrictHostKeyChecking=no root@"$NODE_C_IP" "pkill -f 'ai-memory serve' || true"
sleep 2
PROBE2=$(curl -sS -o /dev/null -w '%{http_code}' \
  -H "X-Agent-Id: ai:probe" -H "Content-Type: application/json" \
  -X POST "http://$NODE_A_PRIV:9077/api/v1/memories" \
  -d "{\"tier\":\"mid\",\"namespace\":\"$NS-probe2\",\"title\":\"probe2-$(date +%s)\",\"content\":\"both-peers-down probe\",\"priority\":5,\"confidence\":1.0,\"source\":\"probe\",\"metadata\":{}}" \
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
