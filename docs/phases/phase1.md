# Phase 1 — Single-node functional

Per-droplet smoke test. The release candidate's binary has to
handle CLI roundtrips, MCP stdio handshake, curator dry-run, and
backup on a fresh droplet before anything downstream is worth
measuring.

Script: [`scripts/phase1_functional.sh`](https://github.com/alphaonedev/ai-memory-ship-gate/blob/main/scripts/phase1_functional.sh).

## Assertions (all must hold per node)

- `ai-memory stats --json` reports `total >= 1` after the seed
  store.
- `ai-memory recall <seed query> --limit 5 --json` returns at
  least one hit.
- `ai-memory backup --to <dir> --keep 1` leaves exactly one
  snapshot + one manifest file.
- `ai-memory curator --once --dry-run --max-ops 10 --json` reports
  at most one error (the "no LLM" case is accepted — Ollama isn't
  on the test droplets).
- `ai-memory mcp` responds to `initialize` + `tools/list` JSON-RPC
  frames with at least 30 tools in the response.

## What failure looks like

Any assertion failing sets `pass: false` with a `reasons: [...]`
list pointing at the specific check. Common causes and fixes:

| Failure | Likely cause | Fix |
|---|---|---|
| `stats.total<1` | cloud-init finished but the write command errored (permissions, disk full) | `df -h` on the droplet; check cloud-init log |
| `mcp.tools<30` | Binary built without semantic feature OR integration test assertion needs update in ai-memory-mcp | Rebuild + rerun |
| `snapshot!=1` | Wrong `--keep` value or prior campaign debris left in `/tmp/ship-gate-backup-<host>` | `rm -rf /tmp/ship-gate-backup-*` and rerun |
| `curator.errors>1` | Non-LLM error from the curator — likely a code regression | Check the curator report's `errors` field |

## Output artefact

`runs/<campaign-id>/phase1-node-<a|b|c>.json` — one file per peer.
