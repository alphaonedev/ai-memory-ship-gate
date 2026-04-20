#!/usr/bin/env bash
# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
#
# Phase 3 — cross-backend migration round-trip + idempotency.
# Runs on node-a. Spins Postgres via docker-compose from the
# ai-memory-mcp repo tree.
#
# Prereqs: the workflow SCP'd /usr/local/bin/ai-memory (pre-built
# with --features sal,sal-postgres on the runner) + copied the
# packaging/ tree to /opt/ai-memory-mcp/packaging/. Docker installed.

set -euo pipefail

log() { printf '[phase3] %s\n' "$*" >&2; }

# The pre-built binary already has both features; we use the same
# invocation name everywhere for readability.
alias ai-memory-sal=/usr/local/bin/ai-memory
shopt -s expand_aliases

cd /opt/ai-memory-mcp

# ---- Start Postgres + pgvector fixture --------------------------
log "docker compose up pgvector"
docker compose -f packaging/docker-compose.postgres.yml up -d
# Wait for pg to accept connections rather than hard sleep.
for i in $(seq 1 30); do
  if docker compose -f packaging/docker-compose.postgres.yml exec -T pgvector \
       pg_isready -U ai_memory -d ai_memory_test 2>/dev/null | grep -q "accepting"; then
    log "postgres ready after ${i}s"; break
  fi
  sleep 1
done

PG_URL="postgres://ai_memory:ai_memory_test@127.0.0.1:5433/ai_memory_test"

# ---- Seed 1000 memories in a fresh sqlite db --------------------
SRC_DB=/tmp/phase3-source.db
rm -f "$SRC_DB"
log "seed 1000 memories into $SRC_DB"
for i in $(seq 1 1000); do
  AI_MEMORY_DB="$SRC_DB" ai-memory-sal store \
    --title "migrate-test-$i" \
    --content "row $i for migration test" \
    --tier mid --namespace phase3 > /dev/null
done

# ---- Forward migration (sqlite -> postgres) ---------------------
log "migrate sqlite -> postgres"
REPORT1=$(ai-memory-sal migrate \
  --from "sqlite://$SRC_DB" \
  --to "$PG_URL" \
  --batch 500 --json)
WRITTEN1=$(echo "$REPORT1" | jq '.memories_written')
READ1=$(echo "$REPORT1" | jq '.memories_read')
ERRORS1=$(echo "$REPORT1" | jq '.errors | length')

# ---- Idempotent re-run ------------------------------------------
log "idempotent re-run"
REPORT2=$(ai-memory-sal migrate \
  --from "sqlite://$SRC_DB" \
  --to "$PG_URL" \
  --batch 500 --json)
WRITTEN2=$(echo "$REPORT2" | jq '.memories_written')
ERRORS2=$(echo "$REPORT2" | jq '.errors | length')

# ---- Reverse migration (postgres -> sqlite) ---------------------
log "reverse migrate postgres -> sqlite"
DST_DB=/tmp/phase3-roundtrip.db
rm -f "$DST_DB"
REPORT3=$(ai-memory-sal migrate \
  --from "$PG_URL" \
  --to "sqlite://$DST_DB" \
  --batch 500 --json)
WRITTEN3=$(echo "$REPORT3" | jq '.memories_written')

# ---- Verify roundtrip identity ----------------------------------
SRC_COUNT=$(AI_MEMORY_DB="$SRC_DB" ai-memory-sal stats --json | jq '.total')
DST_COUNT=$(AI_MEMORY_DB="$DST_DB" ai-memory-sal stats --json | jq '.total')

# ---- Pass/fail --------------------------------------------------
PASS=true; REASONS=()
(( READ1 == 1000 ))      || { PASS=false; REASONS+=("read1=$READ1"); }
(( WRITTEN1 == 1000 ))   || { PASS=false; REASONS+=("written1=$WRITTEN1"); }
(( ERRORS1 == 0 ))       || { PASS=false; REASONS+=("errors1=$ERRORS1"); }
(( WRITTEN2 == 1000 ))   || { PASS=false; REASONS+=("written2=$WRITTEN2 (idempotency)"); }
(( ERRORS2 == 0 ))       || { PASS=false; REASONS+=("errors2=$ERRORS2"); }
(( SRC_COUNT == DST_COUNT )) || { PASS=false; REASONS+=("src=$SRC_COUNT dst=$DST_COUNT"); }

# ---- Teardown Postgres (idempotent) -----------------------------
docker compose -f packaging/docker-compose.postgres.yml down -v || true

jq -n \
  --arg pass "$PASS" \
  --argjson report1 "$REPORT1" \
  --argjson report2 "$REPORT2" \
  --argjson report3 "$REPORT3" \
  --argjson src_count "$SRC_COUNT" \
  --argjson dst_count "$DST_COUNT" \
  --argjson reasons "$(printf '%s\n' "${REASONS[@]}" | jq -R . | jq -s .)" \
  '{phase:3, pass:($pass=="true"), report_forward:$report1, report_idempotent:$report2, report_reverse:$report3,
    src_count:$src_count, dst_count:$dst_count, reasons:$reasons}' | tee /tmp/phase3.json

$PASS || exit 1
