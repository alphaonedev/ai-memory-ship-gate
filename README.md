# ai-memory ship-gate

Reproducible, peer-reviewable release-testing infrastructure for
[ai-memory-mcp](https://github.com/alphaonedev/ai-memory-mcp). Every
release candidate is validated by a four-phase campaign on real
DigitalOcean infrastructure **before a git tag is cut**. Results are
published live to GitHub Pages.

- **Campaign dashboard**: <https://alphaonedev.github.io/ai-memory-ship-gate/>
- **Campaign workflow**: [`.github/workflows/campaign.yml`](.github/workflows/campaign.yml)
- **Per-run artifacts**: [`runs/`](runs/)
- **Governance**: [`docs/governance.md`](docs/governance.md)
- **Latest methodology**: [`docs/methodology.md`](docs/methodology.md)

---

## Governance

ship-gate is the **substrate-only** pre-tag gate for the ai-memory
release train. It produces binary, reproducible substrate evidence
(four phases of shell-driven assertions on real DigitalOcean
droplets) and nothing else. It does not measure NHI behavior, run
LLM-driven agents, or compute treatment effects — those claims are
the exclusive domain of the per-release A2A campaigns under
`ai-memory-a2a-v<release>` that run downstream of a green ship-gate.

The release-train dependency is **substrate first, then NHI**:

```
ship-gate (substrate) ─→ git tag ─→ per-release A2A (substrate cert + NHI playbook)
```

A red ship-gate blocks the tag, which blocks every downstream
campaign. ship-gate findings are joined to NHI-layer correlates
downstream via `ai_memory_git_ref` + `ai_memory_commit` as the
primary join key.

ship-gate's instantiation of the cross-repo First-Principles
governance — which six principles apply, which do not, and how each
applicable principle is realized in the existing four-phase
structure — is in [`docs/governance.md`](docs/governance.md). The
canonical meta-governance lives in
[`ai-memory-ai2ai-gate`](https://github.com/alphaonedev/ai-memory-ai2ai-gate).

---

## The 60-second pitch

Releasing infrastructure software without publishing the evidence of
its correctness is asking users to take it on faith. ai-memory-mcp
does the opposite. Every release candidate runs through this campaign
on fresh DigitalOcean droplets, every phase produces a signed JSON
artifact, every artifact lands in this repository, and every artifact
is rendered into a public web page. If you want to dispute a finding,
fork the repo, point the workflow at your own DigitalOcean account,
and reproduce the run in about fifteen minutes for roughly ten cents.

---

## Why three audiences?

Correctness claims land differently depending on the reader. Three
stakeholders need the same underlying truth filtered through their
own lens:

### 1. For end users (non-technical)

**What does the green "overall_pass" badge on the campaign dashboard
mean for you?**

It means the version of ai-memory you are about to run through
`brew install`, a `.deb` package, a Docker image, or a `cargo install`
passed every test we know how to put it through, on fresh cloud
hardware, within the past few hours. Specifically:

- Your memories write, read, and survive a process restart.
- If you run three ai-memory instances that talk to each other
  (federation mode), a memory written on one shows up on the others.
- If one of those instances crashes mid-write, the survivors don't
  lose data.
- Upgrades between the SQLite and Postgres storage backends don't
  corrupt anything.

You don't have to take our word for any of this. Every artifact —
every write attempt, every crash, every count check — is in this
repository under [`runs/`](runs/). Your IT administrator, your
security reviewer, or your curious teenager can read them.

A green badge is a promise the evidence is there. A red badge means
a release is blocked until we've fixed the thing that failed.

### 2. For C-Level decision makers

**What business risk does this campaign buy down, and at what cost?**

- **Regression risk.** Every release candidate is validated against a
  four-phase protocol that exercises functional, federation,
  migration, and chaos behaviors. Campaign status is a hard gate on
  publishing a git tag; a red campaign means no tag, no package, no
  Docker image. Product can see what is and isn't shippable at any
  moment in time.
- **Audit posture.** Artifacts are immutable, versioned, and public.
  A compliance reviewer asking "how do you know this build is safe
  for production?" gets a URL, not a narrative. Every campaign run is
  signed by GitHub Actions (OIDC via `actions/deploy-pages@v4`) and
  the per-phase JSON reports are pinned to a specific git SHA of
  ai-memory-mcp, so the provenance chain is traceable from "what's
  running in my fleet" back to "which exact test batch validated it".
- **Velocity.** A full campaign completes in ~13-15 minutes on a
  single GitHub Actions runner and four `s-2vcpu-4gb` DigitalOcean
  droplets. Release decisions don't block on multi-hour QA cycles.
- **Cost.** Budget-level impact per run is ~$0.10 of DigitalOcean
  compute (runner-driven SSH methodology; the GitHub-hosted runner
  does the orchestration, droplets hold workload only). A run that
  overruns is capped by an in-droplet dead-man switch at 8 hours
  regardless of workflow state — the worst-case spend ceiling is
  well under $10 per campaign even in pathological failure modes.
- **Peer review.** Any customer, partner, or regulator can reproduce
  the campaign on their own DigitalOcean account and either confirm
  or dispute the result. That is a structurally different posture
  from closed-box vendors attesting their own test suites.

The ROI question is "what would it cost us to discover a silent data-
loss bug in the field?" That number is large. This campaign is
small-number insurance against it.

### 3. For subject-matter experts (engineers, architects, SREs)

**What invariants does the campaign defend, and how?**

| Invariant | Phase | Pass criterion | Root-cause traceability |
|---|---|---|---|
| Single-node CRUD + MCP + curator are functional | 1 | All per-node assertions green | [`scripts/phase1_functional.sh`](scripts/phase1_functional.sh) |
| Write quorum (W=2 of N=3) guarantees eventual consistency on all three peers | 2 | Each node's count ≥ 95% of `ok` after 90s settle; both quorum probes classify correctly | [`scripts/phase2_multiagent.sh`](scripts/phase2_multiagent.sh), [PR #309 federation detach](https://github.com/alphaonedev/ai-memory-mcp/pull/309) |
| SQLite ↔ Postgres migration is idempotent, lossless, symmetric | 3 | `src.total == dst.total`, errors = 0, re-run is a no-op | [`scripts/phase3_migration.sh`](scripts/phase3_migration.sh) |
| Fault-tolerance: `convergence_bound ≥ 0.995` per chaos class | 4 | `min(count_node1, count_node2) / total_ok` across cycles | [`scripts/phase4_chaos.sh`](scripts/phase4_chaos.sh), [PR #312 per-cycle harness](https://github.com/alphaonedev/ai-memory-mcp/pull/312) |

The aggregator (`scripts/collect_reports.sh`) emits a single
`campaign-summary.json` with top-level `overall_pass`. The workflow
fails the build on `overall_pass: false`.

Claim shape for chaos — specifically that we emit a convergence
bound, not a loss probability, and why — is documented in
[ADR-0001 § Chaos-testing methodology](https://github.com/alphaonedev/ai-memory-mcp/blob/release/v0.6.0/docs/ADR-0001-quorum-replication.md).

The [Methodology page](docs/methodology.md) has the full mechanics
per phase, including the settle-time derivation, probe semantics,
and what the metric does and does NOT prove (e.g. it doesn't
establish a real chaos probability, it establishes an observed
empirical floor under the documented fault model).

---

## Goals of the campaign

Every campaign explicitly chases six goals, in priority order. If
you are tempted to add a phase, change a threshold, or rewrite a
script, check that the change strengthens at least one of these.

1. **Catch regressions before they ship.** A red campaign blocks the
   release tag. Nothing bypasses the gate, including "urgent" hot-
   fixes — the urgent fix goes through its own campaign first.
2. **Exercise real infrastructure, not mocks.** Mocks lie about
   timing, about kernel-level partition semantics, about what happens
   when SIGKILL races with an open WAL. Real droplets don't.
3. **Publish evidence, not claims.** Every assertion is paired with
   the artifact that established it. "Phase 2 passed" is a sentence;
   `runs/v0.6.0.0-final-rN/phase2.json` is the thing that makes the
   sentence true.
4. **Keep the methodology peer-reviewable.** Scripts are shell, not
   a DSL. Infrastructure is Terraform, not click-ops. Anyone with a
   DigitalOcean account and this repo can run the exact same test.
5. **Bound cost and blast radius.** Campaigns cost dimes, not
   dollars. A runaway campaign is killed by the in-droplet dead-man
   switch at 8 hours regardless of workflow state. A misconfigured
   workflow cannot exceed its 60-minute single-job ceiling.
6. **Document what the campaign does NOT cover.** LLM-mediated
   paths, benchmark numbers, and week-long soaks are out of scope
   and live elsewhere. See [Methodology § What the methodology does
   NOT cover](docs/methodology.md).

---

## The four phases

| Phase | What it measures | Default budget |
|---|---|---|
| 1 — functional | CRUD, MCP handshake, curator dry-run, backup, per-node assertions | ~30 s across all three nodes in parallel |
| 2 — federation | 4 agents × 50 writes × 3 nodes, 90 s settle, two quorum probes | ~3 min |
| 3 — migration | 1000-memory SQLite → Postgres → SQLite round-trip + idempotency | ~3 min |
| 4 — chaos | 50 cycles × 2 default fault classes (configurable to 4 × 200) | ~6-8 min |

Full details in [Methodology](docs/methodology.md).

---

## Infrastructure

```
 ┌────────────────────────┐          ┌─────────────────────────┐
 │ GitHub Actions runner  │  SSH ──▶ │ chaos-client (1/2)      │
 │ (ubuntu-latest)        │          │  · orchestrates phases  │
 │  · terraform apply     │          │  · runs phase-4 LOCALLY │
 │  · scp + ssh           │          │  · no memory workload   │
 └────────────────────────┘          └─────────────────────────┘
           │
           │  SSH (port 22, public IPs)
           ▼
  ┌──────────────┐   VPC 10.250.0.0/24 (private-only)   ┌──────────────┐
  │ node-a 2/4   │ ◀──────  port 9077  federation ────▶ │ node-b 2/4   │
  │ peer         │                                       │ peer         │
  └──────────────┘                                       └──────────────┘
           │                                                     ▲
           │              ┌──────────────┐                       │
           └────────────▶ │ node-c 2/4   │ ◀─────────────────────┘
                          │ peer         │
                          └──────────────┘
```

- Peer droplets (`s-2vcpu-4gb`): ai-memory serve with
  `--quorum-writes 2 --quorum-peers <other two on VPC>`.
- Chaos client (`s-1vcpu-2gb`): no memory workload; orchestration +
  phase-4 local 3-process harness.
- VPC `10.250.0.0/24` in the configured region (default `nyc3`).
- DO Cloud Firewall: SSH only from the GitHub Actions runner's
  ephemeral egress; port 9077 only from inside the VPC plus the
  runner.

All infrastructure is defined in [`terraform/`](terraform/). The
workflow runs `terraform apply` at campaign start and
`terraform destroy` at teardown regardless of phase outcome.

---

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

Full steps including SSH key handling, VPC conflicts, and how to
dispute a finding by PR: [Reproducing](docs/reproducing.md).

---

## Cost + safety

| Axis | Clean run | Worst-case |
|---|---|---|
| Wall clock | 13-15 min | 8 h (dead-man switch) |
| DO spend | ~$0.10 | < $10 |
| GitHub Actions minutes | 1 job × 15 min | 1 job × 60 min (ceiling) |

Security posture (TLS, mTLS, dead-man switch, key custody) is
documented in [Security](docs/security.md).

---

## Current status

The `v0.6.0.0-final` release train is active. Live status on the
[Actions tab](https://github.com/alphaonedev/ai-memory-ship-gate/actions)
or [latest run](https://alphaonedev.github.io/ai-memory-ship-gate/runs/).
When a campaign returns `overall_pass: true`, the corresponding
ai-memory-mcp commit is tagged and released.

---

## License

Apache-2.0. See [LICENSE](LICENSE).

Copyright © 2026 AlphaOne LLC.
