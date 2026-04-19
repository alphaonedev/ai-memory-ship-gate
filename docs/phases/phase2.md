# Phase 2 — Multi-agent / multi-node federation

The "does the quorum writer actually work when four agents slam
three droplets at once" test. This is where the claim
_"opt-in multi-agent federation with W-of-N quorum writes"_ gets
empirical backing.

Script: [`scripts/phase2_multiagent.sh`](https://github.com/alphaonedev/ai-memory-ship-gate/blob/main/scripts/phase2_multiagent.sh).

## Setup

Each peer is reconfigured to:

```
ai-memory serve \
  --host 0.0.0.0 --port 9077 \
  --quorum-writes 2 \
  --quorum-peers http://<other-a>:9077,http://<other-b>:9077 \
  --quorum-timeout-ms 3000
```

With N=3 peers and W=2, each write needs the originating node + one
remote ack.

## The burst

Four agent identities × 50 concurrent POSTs to node-a:

```
AGENTS = [ai:agent-alice, ai:agent-bob, ai:agent-charlie, ai:agent-dana]
200 writes total, all to /api/v1/memories namespace=ship-gate-phase2
```

Each response is bucketed:

- **201** → ok (quorum met)
- **503** → `quorum_not_met` (acceptable under contention)
- **anything else** → fail (not acceptable)

## Convergence check

After 60 s settle time (six sync-daemon cycles at the default
10 s cadence), count memories in `ship-gate-phase2` namespace on
each peer.

**Pass**: each node's count ≥ 95% of the original `ok` count.

## Quorum probes

Two directed tests confirm the quorum writer distinguishes the
two regimes:

**Probe 1** — kill `ai-memory serve` on node-b, write to node-a.
Expected: 201 (node-a + node-c = quorum met).

**Probe 2** — also kill `ai-memory serve` on node-c, write to node-a.
Expected: 503 with body `{"error":"quorum_not_met","reason":"..."}`.

Both classifications must be correct for the phase to pass.

## Why the probes matter

The burst alone can't distinguish a working quorum writer from a
silently-passing one. The probes prove that:

1. With one peer down, writes succeed via the surviving peer —
   confirming W=2 isn't silently degraded to W=1.
2. With both peers down, writes fail fast with 503 rather than
   hanging or silently succeeding — confirming the quorum
   contract is enforced.

## Output artefact

`runs/<campaign-id>/phase2.json` — single aggregated report.
