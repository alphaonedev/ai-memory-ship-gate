# Phase 3 — Cross-backend migration round-trip

Proves that the v0.7 Storage Abstraction Layer actually works
end-to-end: a SQLite memory store can be migrated into a
Postgres+pgvector store and back, losslessly.

Script: [`scripts/phase3_migration.sh`](https://github.com/alphaonedev/ai-memory-ship-gate/blob/main/scripts/phase3_migration.sh).

## What runs

On node-a:

1. Build ai-memory with `--features sal-postgres`.
2. Start Postgres+pgvector via the in-tree
   `packaging/docker-compose.postgres.yml`.
3. Seed 1000 memories into a fresh SQLite DB.
4. **Forward migrate**: sqlite → postgres.
5. **Idempotent re-run**: same migrate command again.
6. **Reverse migrate**: postgres → fresh sqlite.
7. Compare source and final SQLite counts.
8. Teardown Postgres container.

## Assertions

- `report_forward.memories_read == 1000`
- `report_forward.memories_written == 1000`
- `report_forward.errors == []`
- `report_idempotent.memories_written == 1000` (every row
  overwrites its prior value)
- `report_idempotent.errors == []`
- `src_count == dst_count == 1000` (round-trip preserves cardinality)

## What the phase does NOT test

- **Content fidelity beyond count**. Content-level diff between
  source and destination isn't part of this phase — if a column
  were silently truncated the count would still match. That
  concern is handled by `src/store/postgres.rs` unit tests in
  ai-memory-mcp; phase 3 is the infra smoke test.
- **Performance**. Migration throughput at scale is a benchmark
  matrix question, not a ship gate. See `ROADMAP-ladybug.md` in
  ai-memory-mcp for the comparison plan.
- **Concurrent writes during migration**. The migrate tool doesn't
  claim to handle live writers on the source during migration, and
  this phase doesn't exercise that scenario.

## Why not a managed Postgres DB

DO managed Postgres pricing (~$60/mo tier minimum for pgvector
support at the time of writing) dominates the campaign cost. The
`pgvector/pgvector:pg16` Docker image on node-a delivers identical
semantics for the test shape at $0 marginal cost.

## Output artifact

`runs/<campaign-id>/phase3.json` — forward, idempotent, reverse
reports plus source/destination counts.
