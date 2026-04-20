# Phase 4 — Chaos campaign

The phase that earns the _"W-of-N quorum writes under
injected-failure conditions"_ claim. Uses the in-tree chaos harness
from ai-memory-mcp against the real three-node federation.

Script: [`scripts/phase4_chaos.sh`](https://github.com/alphaonedev/ai-memory-ship-gate/blob/main/scripts/phase4_chaos.sh).

## The four fault classes

| Fault | Mechanism | What it exercises |
|---|---|---|
| `kill_primary_mid_write` | SIGKILL node-0 mid-burst | Recovery after abrupt writer loss |
| `partition_minority` | iptables-drop traffic from node-0 to both peers for 500 ms | Quorum contract under transient partition |
| `drop_random_acks` | SIGSTOP node-1 for 500 ms | Slow/dropped acks without process death |
| `clock_skew_peer` | Simulated skew (full skew needs CAP_SYS_TIME) | Peer-timestamp handling |

Details in `packaging/chaos/run-chaos.sh` in the ai-memory-mcp
repo.

## Per-class campaign

200 cycles × 100 writes per cycle = 20,000 writes per fault class.
80,000 writes total across the phase.

Each cycle:

1. Start clean (or re-use the running federation).
2. Issue `--writes` burst through node-0's HTTP API.
3. Trigger the specified fault.
4. Collect `ok` / `quorum_not_met` / `fail` counts.
5. Record to JSONL.

## Convergence bound

After each campaign, the script computes:

```
convergence_bound = (sum ok across cycles) / (sum writes across cycles)
```

This is an **empirical convergence fraction**, not a loss
probability. See
[ai-memory-mcp/docs/ADR-0001](https://github.com/alphaonedev/ai-memory-mcp/blob/release/v0.6.0/docs/ADR-0001-quorum-replication.md)
§ Chaos-testing methodology for the claim shape.

**Pass**: `convergence_bound ≥ 0.995` for **every** fault class.

## Why 0.995

Quorum writes under stressed conditions cannot reach 1.0 without
infinite retries. The 0.995 floor corresponds to:

- Over 20,000 writes: ≤ 100 `quorum_not_met` responses per class.
- After the sync-daemon converges those writes, the surviving
  count on each peer still matches within 1% of the accepted
  writes.

A campaign that averages much lower than 0.995 indicates the
quorum writer is too brittle under that fault class — a regression
worth investigating before tagging.

## Why clock_skew is simulated

Full clock skew requires either `CAP_SYS_TIME` on the peer
container or a full NTP manipulation — both of which add
operational weight to the campaign infrastructure for limited
benefit. The skew case is simulated (the chaos harness records
the injection intent so the claim shape is honest) while the three
tangible fault classes carry the weight of the phase's evidence.

## Output artifact

`runs/<campaign-id>/phase4.json` — convergence bound per fault
class plus the raw JSONL from each campaign embedded as a
`runs/<campaign-id>/phase4-<fault>.jsonl` artifact (when large).
