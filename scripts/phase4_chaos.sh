#!/usr/bin/env bash
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
#
# Phase 4 — chaos campaign. 200 cycles per fault class × 4 fault
# classes. Runs the in-repo chaos harness from the ai-memory-mcp
# tree on the chaos-client droplet.
#
# Pass criterion per ADR-0001: convergence_bound ≥ 0.995 per class.

set -euo pipefail

: "${NODE_A_IP:?}"
: "${NODE_B_IP:?}"
: "${NODE_C_IP:?}"

log() { printf '[phase4] %s\n' "$*" >&2; }
cd /opt/ai-memory-mcp

CYCLES="${CYCLES:-200}"
WRITES="${WRITES:-100}"

# Chaos harness in-tree expects to spawn its own local processes,
# but for a real-infra campaign we adapt by pointing its curl calls
# at the remote droplets. The in-repo script supports that via the
# N0_PORT/N1_PORT/N2_PORT environment override.

declare -A RESULTS
for FAULT in kill_primary_mid_write partition_minority drop_random_acks clock_skew_peer; do
  log "campaign: $FAULT"
  REPORT_DIR="/tmp/phase4-$FAULT"
  rm -rf "$REPORT_DIR"; mkdir -p "$REPORT_DIR"

  WORKDIR="$REPORT_DIR" \
  AI_MEMORY_BIN="/usr/local/bin/ai-memory" \
  N0_PORT=9077 N1_PORT=9077 N2_PORT=9077 \
  N0_HOST="$NODE_A_IP" N1_HOST="$NODE_B_IP" N2_HOST="$NODE_C_IP" \
    bash packaging/chaos/run-chaos.sh \
      --cycles "$CYCLES" \
      --writes "$WRITES" \
      --fault "$FAULT" \
      --verbose \
      2>&1 | tee "$REPORT_DIR/campaign.log"

  # Extract convergence bound from the per-cycle JSONL summary.
  JSONL="$REPORT_DIR/chaos-report.jsonl"
  if [[ -s "$JSONL" ]]; then
    BOUND=$(jq -s 'def add_or_0(a): (a // 0);
                    (map(.ok) | add_or_0(.)) /
                    (map(.writes) | add_or_0(.) | if . == 0 then 1 else . end)' \
             "$JSONL")
  else
    BOUND=0
  fi
  RESULTS[$FAULT]=$BOUND
  log "$FAULT convergence_bound=$BOUND"
done

# ---- Pass/fail --------------------------------------------------
PASS=true; REASONS=()
for FAULT in "${!RESULTS[@]}"; do
  bound=${RESULTS[$FAULT]}
  # Bash can't do float comparison; use awk.
  ok=$(awk -v b="$bound" 'BEGIN{print (b>=0.995)?1:0}')
  (( ok == 1 )) || { PASS=false; REASONS+=("$FAULT: $bound < 0.995"); }
done

jq -n \
  --arg pass "$PASS" \
  --argjson cycles "$CYCLES" \
  --argjson writes "$WRITES" \
  --argjson results "$(for f in "${!RESULTS[@]}"; do printf '{"%s":%s}\n' "$f" "${RESULTS[$f]}"; done | jq -s 'add')" \
  --argjson reasons "$(printf '%s\n' "${REASONS[@]}" | jq -R . | jq -s .)" \
  '{phase:4, pass:($pass=="true"), cycles_per_fault:$cycles, writes_per_cycle:$writes,
    convergence_by_fault:$results, reasons:$reasons}' | tee /tmp/phase4.json

$PASS || exit 1
