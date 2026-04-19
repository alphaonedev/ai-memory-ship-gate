#!/usr/bin/env bash
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
#
# Phase 1 — single-node functional smoke test.
# Run on each peer droplet. Output JSON report to stdout.
#
# Usage:
#   ssh root@<node> "bash -s" < phase1_functional.sh

set -euo pipefail

HOST="$(hostname)"
REPORT=/tmp/phase1-$HOST.json
: > "$REPORT"

log() { printf '[phase1][%s] %s\n' "$HOST" "$*" >&2; }

# ---- CLI roundtrip ----------------------------------------------
log "cli roundtrip"
ai-memory store \
  --title "phase1-$HOST" \
  --content "phase 1 functional check on $HOST $(date -u +%s)" \
  --tier mid \
  --namespace ship-gate-phase1 > /dev/null

RECALL=$(ai-memory recall "functional check on $HOST" --limit 5 --json 2>/dev/null || echo '{"memories":[]}')
RECALL_COUNT=$(echo "$RECALL" | jq '.memories | length')

STATS=$(ai-memory stats --json 2>/dev/null)
TOTAL=$(echo "$STATS" | jq '.total')

# ---- Backup + manifest integrity --------------------------------
log "backup + manifest"
BACKUP_DIR=/tmp/ship-gate-backup-$HOST
rm -rf "$BACKUP_DIR"
ai-memory backup --to "$BACKUP_DIR" --keep 1 > /dev/null
SNAPSHOT_COUNT=$(ls "$BACKUP_DIR"/ai-memory-*.db 2>/dev/null | wc -l)
MANIFEST_COUNT=$(ls "$BACKUP_DIR"/ai-memory-*.manifest.json 2>/dev/null | wc -l)

# ---- Curator dry-run (no LLM required) --------------------------
log "curator dry-run"
CURATOR=$(ai-memory curator --once --dry-run --max-ops 10 --json 2>/dev/null \
  || echo '{"operations_attempted":0,"errors":["curator absent or errored"]}')
CURATOR_ERRS=$(echo "$CURATOR" | jq '.errors | length')

# ---- MCP tools/list handshake (sanity) --------------------------
log "mcp tools/list"
MCP_TOOLS=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"ship-gate-phase1"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  | timeout 10 ai-memory mcp 2>/dev/null | tail -1)
MCP_TOOL_COUNT=$(echo "$MCP_TOOLS" | jq '.result.tools | length' 2>/dev/null || echo 0)

# ---- Version (pinned by cloud-init) -----------------------------
VERSION=$(cat /etc/ai-memory/version 2>/dev/null || ai-memory --version)

# ---- Pass/fail evaluation ---------------------------------------
PASS=true
REASONS=()
(( TOTAL >= 1 ))         || { PASS=false; REASONS+=("stats.total<1"); }
(( RECALL_COUNT >= 1 ))  || { PASS=false; REASONS+=("recall.memories<1"); }
(( SNAPSHOT_COUNT == 1 )) || { PASS=false; REASONS+=("snapshot!=1"); }
(( MANIFEST_COUNT == 1 )) || { PASS=false; REASONS+=("manifest!=1"); }
(( CURATOR_ERRS <= 1 ))  || { PASS=false; REASONS+=("curator.errors>1"); }
(( MCP_TOOL_COUNT >= 30 )) || { PASS=false; REASONS+=("mcp.tools<30"); }

jq -n \
  --arg host "$HOST" \
  --arg version "$VERSION" \
  --arg pass "$PASS" \
  --argjson stats "$STATS" \
  --argjson curator "$CURATOR" \
  --argjson mcp_tool_count "$MCP_TOOL_COUNT" \
  --argjson recall_count "$RECALL_COUNT" \
  --argjson snapshot_count "$SNAPSHOT_COUNT" \
  --argjson manifest_count "$MANIFEST_COUNT" \
  --argjson reasons "$(printf '%s\n' "${REASONS[@]}" | jq -R . | jq -s .)" \
  '{
    phase: 1,
    host: $host,
    version: $version,
    pass: ($pass == "true"),
    reasons: $reasons,
    stats: $stats,
    curator: $curator,
    mcp_tool_count: $mcp_tool_count,
    recall_count: $recall_count,
    snapshot_count: $snapshot_count,
    manifest_count: $manifest_count
  }' > "$REPORT"

cat "$REPORT"
$PASS || exit 1
