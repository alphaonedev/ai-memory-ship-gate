# ai-memory ship-gate

Reproducible release-testing for
[ai-memory-mcp](https://github.com/alphaonedev/ai-memory-mcp).

## Why this site exists

Every release candidate for `ai-memory-mcp` is validated by a
four-phase campaign on real DigitalOcean infrastructure **before a
tag is cut**. This site is the canonical home for:

- **Campaign artefacts.** Every run commits its per-phase JSON reports
  plus the aggregated summary to [`runs/<campaign-id>/`](runs/) in
  the repo. The site re-renders them as browsable pages.
- **Methodology.** Exactly how each phase is measured, what pass/fail
  means, what hardware was used.
- **Reproducibility.** Fork the repo, bring your own DigitalOcean
  token, re-run. All scripts, all Terraform, all dashboards are
  versioned here.
- **Peer review.** Dispute a finding by opening a PR that reproduces
  it on your own account.

## The four phases

| Phase | What it measures | Pass criterion |
|---|---|---|
| 1 — functional | CRUD, MCP handshake, curator dry-run, backup | All per-node assertions green |
| 2 — federation | 4 agents × 50 writes × 3 nodes, quorum-probe | ≥ 95% convergence; both probes classify correctly |
| 3 — migration | 1000-memory SQLite↔Postgres round-trip + idempotency | reads = writes, errors = 0, counts identical |
| 4 — chaos | 200 cycles × 4 fault classes | `convergence_bound ≥ 0.995` per class |

See [Methodology](methodology.md) for the mechanics of each phase.

## Current release gate

`v0.6.0.0` — in flight. Tag happens when the campaign returns a full
`overall_pass: true` verdict.

Track the live status on the [Actions
tab](https://github.com/alphaonedev/ai-memory-ship-gate/actions)
or see the latest run under
[Campaign runs](runs/).

## Reproducing a run

```sh
gh repo fork alphaonedev/ai-memory-ship-gate --clone
gh secret set DIGITALOCEAN_TOKEN -R <your-fork>           # encrypted at rest
gh secret set DIGITALOCEAN_SSH_KEY_FINGERPRINT -R <your-fork>
gh secret set DIGITALOCEAN_SSH_PRIVATE_KEY -R <your-fork> # < ~/.ssh/id_ed25519
gh workflow run campaign.yml -R <your-fork> \
  -f ai_memory_git_ref=release/v0.6.0 \
  -f campaign_id=my-validation-run
```

Detailed steps: [Reproducing](reproducing.md).

## Cost per run

~$0.65 for a clean ~5-hour run. ~$1.05 overruns. The in-droplet
dead-man switch caps uptime at 8 hours regardless of workflow state
— see [Security](security.md).
