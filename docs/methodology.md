# Methodology

This page is the authoritative description of how each phase is
measured. If the phase script and this page disagree, **the script
wins** — file an issue pointing at the discrepancy.

## Hardware per campaign

| Role | Droplet | Why that size |
|---|---|---|
| node-a, node-b, node-c | `s-2vcpu-4gb` | Enough RAM for the HNSW index on a 1000-memory corpus plus Ollama-free LLM-surface checks |
| chaos-client | `s-1vcpu-2gb` | No memory workload; drives curl loops and ssh |
| Region | `nyc3` by default | Low operator latency; configurable via workflow input |

All droplets are Ubuntu 24.04 LTS. cloud-init clones `ai-memory-mcp`
at the specified git ref and builds it from source with
`cargo build --release`.

## Pass/fail aggregation

Every phase script emits a single JSON report with a top-level
`pass: true|false` + `reasons: [...]` on fail. The aggregator
(`collect_reports.sh`) produces a campaign summary with
`overall_pass` = all-phases-pass. The workflow fails the build if
`overall_pass` is false.

## Phase 1 — single-node functional

For each peer droplet:

1. Store one memory via CLI.
2. Recall it back, asserting ≥ 1 result.
3. Pull stats via CLI, asserting `total >= 1`.
4. Run `ai-memory backup --to /tmp/ship-gate-backup-<host>` and
   assert exactly one snapshot + one manifest file exist.
5. Run `ai-memory curator --once --dry-run --max-ops 10 --json`
   and assert errors count ≤ 1 (the "no LLM client configured"
   case is accepted — Ollama isn't on the droplets).
6. Send `initialize` + `tools/list` JSON-RPC frames to
   `ai-memory mcp` over stdio. Assert tool count ≥ 30.

Fails on any unsatisfied assertion.

## Phase 2 — multi-agent / multi-node federation

One-time setup: reconfigure each peer with
`--quorum-writes 2 --quorum-peers <other two>`.

### Write burst

Four agent identities (`ai:agent-alice`, `-bob`, `-charlie`, `-dana`)
each issue 50 concurrent POSTs to `http://node-a:9077/api/v1/memories`
in namespace `ship-gate-phase2`. 200 writes total.

Each response is bucketed:
- 201 → ok
- 503 → quorum_not_met (acceptable under contention)
- other → fail

### Settle + convergence

After 90 s of settle time (sync-daemon default cadence is 2 s after
PR #309; allow ample headroom), list every peer's
`/api/v1/memories?namespace=ship-gate-phase2&limit=1000` and capture
the count.

**Pass**: each node's count ≥ 95% of `ok`.

### Quorum probes

1. **Probe 1** — kill `ai-memory serve` on node-b. Submit a write to
   node-a with default `--quorum-writes 2`. Should return **201**
   (node-a commits locally + node-c acks = quorum met).
2. **Probe 2** — also kill `ai-memory serve` on node-c. Submit a
   write. Should return **503** (no peer acks = quorum not met).

Both classifications are required for pass.

## Phase 3 — cross-backend migration

On node-a:

1. `cargo build --release --features sal-postgres`.
2. `docker compose -f packaging/docker-compose.postgres.yml up -d`.
3. Seed 1000 memories into a fresh `/tmp/phase3-source.db`.
4. Forward migrate sqlite → postgres.
5. Re-run the same migrate (idempotency).
6. Reverse migrate postgres → fresh sqlite.
7. Assert `src.total == dst.total == 1000` and all error counts 0.

Teardown kills the Postgres container.

## Phase 4 — chaos campaign

From the chaos-client, run `packaging/chaos/run-chaos.sh` LOCALLY on
that droplet (the harness spawns three ai-memory processes on ports
`19077/19078/19079` under per-cycle DB isolation). The peer nodes in
the VPC are not used by phase 4 — signal-level fault injection
(SIGKILL / SIGSTOP) and iptables rules require local root, and
ADR-0001's campaign shape is satisfied by the local harness. Four
fault classes:

1. `kill_primary_mid_write` — SIGKILL node-0 mid-burst.
2. `partition_minority` — iptables-drop traffic from node-0 to both
   other peers mid-burst, restore after 500 ms.
3. `drop_random_acks` — SIGSTOP node-1 for 500 ms mid-burst.
4. `clock_skew_peer` — simulated (full CAP_SYS_TIME skew requires
   NTP manipulation; we record the intent).

Ship-gate default: 50 cycles × 100 writes/cycle per fault class.
Bump `CHAOS_CYCLES=200` on workflow dispatch for a full soak.

The convergence bound (PR #312 metric) is:

```
min(count_node1_per_cycle, count_node2_per_cycle) / total_ok
```

— the fraction of writes that returned 201 AND subsequently landed
on both live peers. Earlier versions used `ok / total_writes`, which
was mathematically capped at ~2% for kill-type faults and made the
0.995 threshold unreachable (see the run-17/18 post-mortem in the
campaign artifacts).

**Pass per class**: convergence_bound ≥ 0.995.
**Pass overall**: all enabled classes pass.

## Per-phase timeouts (runner-driven methodology, commit `f81bd76`)

Under the current runner-driven SSH methodology, the GitHub Actions
runner orchestrates; the droplets execute. Typical clean run is
13-15 minutes wall clock (not the 60-minute per-droplet baseline of
earlier methodologies).

- Phase 1: ~30 s (SSH + CLI ops per node, parallel).
- Phase 2: ~3 min (write burst + 90 s settle + probes).
- Phase 3: ~3 min (build + Postgres boot + migrations).
- Phase 4: ~6-8 min (50 cycles × 2 default fault classes).

The workflow has a hard 60-minute ceiling on the single job. The
in-droplet dead-man switch destroys infrastructure after 8 hours
regardless — cost cap of last resort.

## What the methodology does NOT cover

- **LLM-mediated paths.** Ollama is not installed on the test
  droplets (bumping to `s-4vcpu-16gb` for Gemma 4 E2B would raise
  per-run cost 3×). Curator is exercised only in `--dry-run`. The
  week-long soak (`RUNBOOK-curator-soak.md` in ai-memory-mcp) covers
  that workload separately.
- **Real chaos probability claims.** The phase-4 output is a
  convergence bound, not a loss probability. See
  [ADR-0001](https://github.com/alphaonedev/ai-memory-mcp/blob/release/v0.6.0/docs/ADR-0001-quorum-replication.md)
  § Chaos-testing methodology for the claim shape we defend.
- **Benchmarks.** Throughput / latency numbers aren't this
  campaign's job; the benchmark matrix is a separate v0.7.1
  deliverable (see `ROADMAP-ladybug.md` in ai-memory-mcp).
