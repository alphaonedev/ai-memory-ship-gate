# ai-memory ship-gate

<!--
  Latest release banner is rendered from releases/<highest-semver>/summary.json
  by the `render_current_release` macro defined in ../main.py. To bump the
  surfaced release, add a new releases/<vX.Y.Z>/summary.json with verdict
  "pass" — no edits to this file required. Schema lives in releases/schema.json
  and is enforced on tag push by .github/workflows/release-summary-gate.yml.
-->
{{ render_current_release() }}

Reproducible release-testing for
[ai-memory-mcp](https://github.com/alphaonedev/ai-memory-mcp).
Every release candidate is validated by a four-phase campaign on
real DigitalOcean infrastructure **before a git tag is cut**. This
site is where the evidence is published.

- [Latest campaign runs](runs/) · live dashboard of every attempt
- [Methodology](methodology.md) · exactly what each phase measures
- [14-day soak](soak.md) · long-horizon stability testing (84 runs per release, every 4h)
- [Reproducing](reproducing.md) · run it yourself on your own DO account
- [Security](security.md) · TLS, mTLS, dead-man switch, key custody

---

## The 60-second pitch

Releasing infrastructure software without publishing the evidence of
its correctness is asking users to take it on faith. ai-memory-mcp
does the opposite. Every release candidate runs through this campaign
on fresh DigitalOcean droplets, every phase produces a JSON artifact,
every artifact lands in this repository, and every artifact is
rendered into a browsable page on this site. If you want to dispute a
finding, fork the repo, point the workflow at your own DigitalOcean
account, and reproduce the run in about fifteen minutes for roughly
ten cents.

---

## What this means to you

Correctness claims land differently depending on who's reading. Three
audiences, same underlying truth, three framings:

=== "End users (non-technical)"

    **What does the green "overall_pass" badge on a campaign page
    mean for you?**

    It means the version of ai-memory you are about to install via
    `brew`, `apt`, Docker, or `cargo install` passed every test we
    know how to put it through, on fresh cloud hardware, within the
    past few hours. Specifically:

    - Your memories write, read, and survive a process restart.
    - If you run three ai-memory instances that talk to each other,
      a memory written on one shows up on the others.
    - If one of those instances crashes mid-write, the survivors
      don't lose data.
    - Upgrades between SQLite and Postgres storage don't corrupt
      anything.

    You don't have to take our word for any of this. Every artifact
    — every write attempt, every crash, every count check — is
    linked from [Campaign runs](runs/). Your IT administrator, your
    security reviewer, or your curious teenager can read them.

    A green badge is a promise the evidence is there. A red badge
    means a release is blocked until we've fixed whatever failed.

=== "C-Level decision makers"

    **What business risk does this campaign buy down, at what cost?**

    - **Regression risk.** Every release candidate is validated
      against a four-phase protocol that exercises functional,
      federation, migration, and chaos behaviors. Campaign status
      is a hard gate on publishing a git tag. A red campaign means
      no tag, no package, no Docker image. Product leadership can
      see what is and isn't shippable at any moment in time.
    - **Audit posture.** Artifacts are immutable, versioned, and
      public. A compliance reviewer asking "how do you know this
      build is safe for production?" gets a URL, not a narrative.
      Every campaign run is signed by GitHub Actions (OIDC) and
      pinned to a specific git SHA, so provenance is traceable from
      "what's running in my fleet" back to "which exact test batch
      validated it".
    - **Velocity.** A full campaign completes in ~13-15 minutes.
      Release decisions don't block on multi-hour QA cycles.
    - **Cost.** ~$0.10 of DigitalOcean compute per clean run under
      the runner-driven SSH methodology. In-droplet dead-man switch
      caps worst-case spend at well under $10 per run even in
      pathological failure modes.
    - **Peer review.** Any customer, partner, or regulator can
      reproduce the campaign on their own account and confirm or
      dispute the result. Structurally different from closed-box
      vendors attesting their own test suites.

    **ROI framing.** The question is "what would a silent data-loss
    bug in the field cost us?" That number is large. This campaign
    is small-number insurance against it.

=== "Engineers / architects / SREs"

    **What invariants does the campaign defend, and how?**

    | Invariant | Phase | Pass criterion |
    |---|---|---|
    | Single-node CRUD + MCP + curator functional | 1 | All per-node assertions green |
    | Quorum writes (W=2/N=3) eventually consistent on all three peers | 2 | Each node's count ≥ 95% of `ok` after 90 s settle; both quorum probes classify correctly |
    | SQLite ↔ Postgres migration idempotent + lossless | 3 | `src.total == dst.total`, errors = 0, re-run no-op |
    | Fault tolerance: `convergence_bound ≥ 0.995` per chaos class | 4 | `min(count_node1, count_node2) / total_ok` across cycles |

    The aggregator (`scripts/collect_reports.sh`) emits a single
    `campaign-summary.json` with top-level `overall_pass`. The
    workflow fails the build on `overall_pass: false`.

    Claim shape for chaos — specifically that we emit a convergence
    bound, not a loss probability, and why — is documented in
    [ADR-0001 § Chaos-testing methodology](https://github.com/alphaonedev/ai-memory-mcp/blob/release/v0.6.0/docs/ADR-0001-quorum-replication.md).
    The full mechanics per phase, including settle-time derivation,
    probe semantics, and what the metric does and does NOT prove,
    live in [Methodology](methodology.md).

---

## Goals of the campaign

Every campaign chases six goals, in priority order. If a change
doesn't strengthen one of these, it doesn't belong.

1. **Catch regressions before they ship.** A red campaign blocks
   the release tag. No bypass paths — urgent hotfixes go through
   their own campaign first.
2. **Exercise real infrastructure, not mocks.** Mocks lie about
   timing, about kernel-level partition semantics, about SIGKILL
   racing with an open WAL. Real droplets don't.
3. **Publish evidence, not claims.** Every assertion is paired with
   the artifact that established it. Sentences aren't truth;
   `runs/<campaign>/phase2.json` is the thing that makes sentences
   true.
4. **Keep the methodology peer-reviewable.** Scripts are shell, not
   a DSL. Infrastructure is Terraform, not click-ops. Anyone with
   a DigitalOcean account and this repo can run the exact same
   test.
5. **Bound cost and blast radius.** Campaigns cost dimes, not
   dollars. A runaway campaign is killed by the in-droplet dead-man
   switch at 8 hours regardless of workflow state. A misconfigured
   workflow cannot exceed its 60-minute single-job ceiling.
6. **Document what the campaign does NOT cover.** LLM-mediated
   paths, benchmark numbers, and week-long soaks are out of scope
   and live elsewhere — see [Methodology § What the methodology does
   NOT cover](methodology.md).

---

## The four phases

| Phase | Measures | Default budget |
|---|---|---|
| [1 — functional](phases/phase1.md) | CRUD, MCP handshake, curator dry-run, backup | ~30 s (3 nodes in parallel) |
| [2 — federation](phases/phase2.md) | 4 agents × 50 writes × 3 nodes, 90 s settle, quorum probes | ~3 min |
| [3 — migration](phases/phase3.md) | 1000-memory SQLite → Postgres → SQLite round-trip | ~3 min |
| [4 — chaos](phases/phase4.md) | 50 cycles × 2 default fault classes (configurable) | ~6-8 min |

Full mechanics: [Methodology](methodology.md).

---

## Infrastructure

| Component | Size | Role |
|---|---|---|
| `node-a`, `node-b`, `node-c` | `s-2vcpu-4gb` | Peer nodes for quorum mesh + migration host |
| `chaos-client` | `s-1vcpu-2gb` | Orchestration + Phase 4 local 3-process harness |
| VPC | `10.250.0.0/24` in region | Peer-to-peer federation (port 9077) is VPC-only |
| Firewall | DO Cloud Firewall | SSH from runner; 9077 from VPC + runner only |

All infrastructure is defined in
[`terraform/`](https://github.com/alphaonedev/ai-memory-ship-gate/tree/main/terraform).
The workflow runs `terraform apply` at campaign start and
`terraform destroy` at teardown regardless of phase outcome.

---

## Release history

Every released `vX.Y.Z` ships a `releases/<version>/summary.json` artifact
that this page reads at build time. The highest-semver entry is the headline
banner above; the table below lists every published release in reverse-chronological
order. See [Campaign runs](runs/) for every campaign attempt (including failed
runs) per release.

{{ render_release_history() }}

The schema for `summary.json` lives in
[`releases/schema.json`](https://github.com/alphaonedev/ai-memory-ship-gate/blob/main/releases/schema.json).
Pushing a `v*` tag without a matching `releases/<tag>/summary.json` fails the
release-blocking [`release-summary-gate`](https://github.com/alphaonedev/ai-memory-ship-gate/actions/workflows/release-summary-gate.yml)
workflow before any artifact is published.

---

## Cost per run

~$0.10 for a clean ~15-minute run under the runner-driven SSH
methodology (commit `f81bd76`) — the GitHub Actions runner holds
orchestration, four DigitalOcean droplets hold workload. The
in-droplet dead-man switch still caps uptime at 8 hours regardless
of workflow state — see [Security](security.md).
