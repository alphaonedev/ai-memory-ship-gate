# ai-memory ship-gate — First-Principles governance overlay

**Substrate-only pre-tag gate. Substrate evidence stream for ai-memory-mcp.**

---

## Document control

| Field | Value |
|---|---|
| Subject under test | `ai-memory-mcp` (whichever git ref the campaign was dispatched against) |
| Gate role | **Substrate-only** pre-tag gate. Runs on RC droplets before any release tag is cut. |
| Truth-claim covered | Claim A — substrate correctness. Claim B (substrate utility / NHI behavior) is covered by per-release A2A campaigns downstream. |
| Canonical governance home | [`alphaonedev/ai-memory-ai2ai-gate/docs/governance/META-GOVERNANCE.md`](https://github.com/alphaonedev/ai-memory-ai2ai-gate) (in flight; see `<placeholder: ai2ai-gate#TBD>` until the meta-governance PR lands). This document is the ship-gate **instantiation** of that meta-governance and defers to it on any conflict. |
| Sibling instantiations | [`ai-memory-a2a-v0.6.3.1/docs/governance.md`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/refactor/first-principles-governance/docs/governance.md) and the per-release A2A campaigns that follow it. |
| Existing methodology | [`docs/methodology.md`](methodology.md) and [`docs/phases/`](phases/) describe **what** each phase measures. This document describes **why**, under First-Principles. The two are non-overlapping; the methodology page wins on mechanics, this page wins on governance posture. |
| Document audience | Release-train operator, NHI Orchestrator running per-release A2A campaigns, external auditors. |
| Document scope | Governance overlay only. No script, terraform, workflow, or per-phase doc is modified by this document. |

---

## 1. Why this document exists

The `ai-memory` testing topology currently spans three repositories:

1. **`ai-memory-ship-gate`** (this repo) — pre-tag substrate gate. Four-phase campaign on DigitalOcean RC droplets. Shell scripts, real infrastructure, binary pass/fail per phase. **Substrate-only.**
2. **`ai-memory-ai2ai-gate`** — A2A specification + testbook + meta-governance. Defines the schema, the phase model, and the cross-repo conventions every campaign repo inherits.
3. **`ai-memory-a2a-v<release>`** — per-release A2A campaigns. Substrate cert (mirrors the ship-gate posture for A2A surfaces) **plus** an autonomous NHI playbook layer that exercises ai-memory through real Claude-driven agents.

A new "First-Principles governance" document (canonical home: `ai2ai-gate/docs/governance/META-GOVERNANCE.md`, currently in flight) defines six principles every testing campaign in the topology must instantiate. The per-release A2A campaign for v0.6.3.1 has already authored its instantiation; see [PR #2 in `ai-memory-a2a-v0.6.3.1`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/pull/2).

ship-gate is structurally different from a per-release A2A campaign. It is **substrate-only**: it tests ai-memory's correctness directly via shell scripts, with no autonomous LLM-driven agents reasoning over memory. So not all six principles apply, and the two that govern *evidence shape* (Principles 4 and 5) realize differently here than they do in a campaign with an NHI layer.

This document is ship-gate's First-Principles instantiation. It explains which principles apply, which do not, and how each applicable principle is realized in ship-gate's existing four-phase structure — without touching any of that structure.

---

## 2. The six principles, applied to ship-gate

| # | Principle | Applies to ship-gate? | How |
|---|---|---|---|
| 1 | Two truth-claims (substrate vs utility) — separate evidence streams | **Yes** | ship-gate produces only the substrate evidence stream (Claim A). It does not, and must not, attempt to make utility claims. |
| 2 | Substrate first — gate the playbook on substrate green | **Yes** | ship-gate **is** the substrate gate. A red ship-gate blocks the release tag, which blocks every downstream campaign that depends on a tagged release. |
| 3 | Tasks must require context — for NHI scenarios | **No** | ship-gate has no NHI layer. There are no LLM-driven agent turns to ground. This principle is non-applicable here and is fully covered by the per-release A2A campaigns. |
| 4 | Structured JSON for machine review (§7 schema in the canonical doc) | **Partial** | The canonical §7 schema is for NHI per-turn records and does not apply directly. ship-gate's analog is the per-phase JSON reports validated against [`releases/schema.json`](../releases/schema.json). This document adds a parallelism field (`nhi_verdict`) to that schema so consumers can join ship-gate findings to NHI-layer correlates. |
| 5 | Cross-layer consistency — strongest evidence type | **Yes (as a producer)** | ship-gate findings (e.g. "Phase 2 federation convergence ≥ 95% within 90 s settle at quorum=2") are the substrate-layer correlates that per-release A2A NHI scenarios join against. ship-gate produces the metadata that makes the join possible. |
| 6 | Scope discipline — node, agents, release tagged in every artifact | **Yes** | Every artifact already carries `ai_memory_git_ref`, `ai_memory_commit`, `campaign_run_id`, `version`. This document codifies that the same fields are used as the join keys for cross-layer consistency. |

The remaining sections expand each applicable principle.

---

## 3. Principle 1 — substrate-only evidence stream

### What ship-gate claims

ship-gate makes exactly one truth-claim per campaign: **the four-phase substrate protocol passed (or failed) at this exact `ai_memory_git_ref` on this exact droplet topology, at this exact wall-clock time, with these exact assertion counts.**

That is Claim A from the canonical First-Principles document, narrowed to ship-gate's four-phase scope:

- **Phase 1 — functional.** CRUD, MCP handshake, curator dry-run, backup, per-node assertions on three peer droplets.
- **Phase 2 — federation.** 4 agents × 50 writes × 3 nodes, 90 s settle, both quorum probes classified.
- **Phase 3 — migration.** SQLite → Postgres → SQLite round-trip + idempotency on a 1000-memory corpus.
- **Phase 4 — chaos.** N cycles × default fault classes; pass requires `convergence_bound ≥ 0.995`.

Evidence is binary and reproducible. Every assertion is a shell-script exit code. The aggregator `scripts/collect_reports.sh` collapses the four per-phase reports into one `campaign-summary.json` with top-level `overall_pass`.

### What ship-gate does NOT claim

ship-gate makes **no** utility claim. It does not measure whether ai-memory changes the behavior of an LLM-driven agent. It does not run NHIs. It does not compute grounding rates, hallucination rates, treatment effects, or cross-arm comparisons. Those claims are the exclusive domain of the per-release A2A campaigns that run after a green ship-gate produces a tagged release.

If a future change to ship-gate would introduce any LLM-mediated path, it must first be authored in `ai2ai-gate` as a meta-governance update, then instantiated separately in this document. Slipping NHI evidence into a substrate cert weakens the substrate cert's standing — substrate evidence is binary, NHI evidence is statistical, mixing them invites readers to discount both.

This separation is enforced structurally by `nhi_verdict: null` in `releases/<version>/summary.json` (see §6).

---

## 4. Principle 2 — substrate first, gate downstream on green

ship-gate is the substrate gate for the entire ai-memory release train. Its position in the dependency graph is:

```
  ┌──────────────────────────┐
  │   ship-gate campaign     │  ← this repo, 4-phase substrate
  │   on RC droplets         │
  └──────────────┬───────────┘
                 │ overall_pass: true
                 ▼
        ┌──────────────────┐
        │   git tag cut    │
        └────────┬─────────┘
                 │
                 ▼
   ┌──────────────────────────────┐
   │  per-release A2A campaign    │  ← ai-memory-a2a-v<release>
   │   · substrate cert (mirror)  │
   │   · NHI playbook (Phase 3)   │
   │   · meta-analysis (Phase 4)  │
   └──────────────────────────────┘
```

Operating consequences:

- A `verdict: fail` in any ship-gate phase **blocks the release tag**. No tag, no per-release campaign, no NHI playbook, no downstream evidence.
- The per-release A2A campaign is a **downstream consumer** of the ship-gate verdict. Its Phase 1 (substrate cert) is allowed to assume the ship-gate level is green; if it isn't, the downstream campaign halts at its own entry gate per the canonical doc's Principle 2.
- A "harness-integrity" failure in ship-gate (Phase 2 quorum probes don't classify, Phase 4 convergence emits NaN, schema-gate workflow rejects a `summary.json`) is treated identically to a phase failure: the campaign is red, the tag is blocked, the operator files a harness-integrity issue rather than overriding the gate.

ship-gate has no analog of S23/S24 in the per-release A2A campaign — there are no expected-RED canaries today. §8 below is the forward-looking commitment to add one.

---

## 5. Principle 4 — structured JSON, the ship-gate way

The canonical First-Principles §7 schema describes NHI per-turn records: `turn_id`, `claims_made`, `claims_grounded`, `tools_called`, etc. None of those concepts exist in ship-gate, and grafting them on would be cargo-culting.

ship-gate's analog is the per-phase JSON report. Each phase script emits a single object with `pass: bool`, the assertions it ran, the counts it observed, and the timing it measured. Those four objects are aggregated into `runs/<campaign-id>/campaign-summary.json` and into the release surface `releases/<version>/summary.json`.

The release-surface schema is [`releases/schema.json`](../releases/schema.json). It is enforced on every `v*` tag push by `.github/workflows/release-summary-gate.yml`. **This document adds one field to that schema** to make ship-gate parallel with the per-release A2A campaign's release surface:

- **`nhi_verdict`** — top-level, sibling to `verdict`. For ship-gate this is **always `null`**, which encodes "ship-gate is substrate-only; the NHI verdict for this release is provided by the per-release A2A campaign that runs after this gate passes." Consumers (the test-hub aggregator, the `ai-memory-test-hub` rollup, external auditors) can read either schema and not crash on a missing field.

The schema-level docstring on `nhi_verdict` codifies this contract. See `releases/schema.json` for the binding text.

No other schema changes. The existing `verdict` field continues to mean exactly what it has always meant: substrate four-phase pass/fail.

---

## 6. Principle 5 — cross-layer consistency, ship-gate as producer

ship-gate sits one layer below the per-release A2A campaign in the testing stack. Many ship-gate findings have an NHI-layer correlate:

| ship-gate finding (substrate) | Per-release A2A NHI correlate (utility) |
|---|---|
| Phase 1 — MCP `tools/list` returns ≥ 30 tools | NHI playbook Phase 2 dry-run discovers and calls those tools |
| Phase 2 — federation convergence ≥ 95% within 90 s settle at quorum=2 | NHI Scenario D (federation honesty) — Hermes recall on node-2 within the same settle window |
| Phase 2 — Probe 2 returns 503 when 2/3 peers down | NHI scenarios depending on cross-agent visibility degrade gracefully when quorum is unmet |
| Phase 3 — SQLite ↔ Postgres round-trip lossless | NHI scenarios that span a backend-migration window observe no recall regression |
| Phase 4 — `convergence_bound ≥ 0.995` under chaos class | NHI Scenario C (correction memory) survives the same chaos class without returning stale F |

ship-gate's job under Principle 5 is **to make the join possible**, not to compute the consistency table itself. The consistency table is computed by the per-release A2A campaign's Phase 4 meta-analyst (see canonical §8.3).

For the join to work, every ship-gate artifact must carry the join keys the meta-analyst needs:

- `campaign_id` — already present as `campaign_run_id` in `releases/<version>/summary.json` and per-phase reports.
- `ai_memory_git_ref` — already present in the release summary and embedded in every per-run artifact under `runs/<campaign-id>/`.
- `ai_memory_commit` — already present in the release summary; resolves the git ref to a specific SHA.
- `version` — already present.
- `node_id` — already implicit in per-phase reports via the per-droplet hostname keys; the per-release A2A campaign carries this as `node_id=do-<id>`.

**Convention for joining ship-gate findings to NHI correlates:**

A per-release A2A campaign's meta-analyst joins a ship-gate finding to its NHI correlate by:

1. Taking the `ai_memory_git_ref` (or `ai_memory_commit`) from the per-release campaign's own metadata.
2. Looking up the matching ship-gate `releases/<version>/summary.json` whose `ai_memory_git_ref` (or `ai_memory_commit`) matches.
3. Reading that summary's `phases` array for substrate verdicts.
4. Pairing each row of the consistency table with the corresponding ship-gate phase finding.

The `ai_memory_git_ref` is the **primary join key**. `ai_memory_commit` is the tie-breaker when a ref points to a moving branch. `campaign_run_id` is for forensic correlation (which exact ship-gate run produced this evidence) but is not used as a join key, since the per-release campaign may run against the tagged release some time after ship-gate produced its verdict.

ship-gate's commitment under this convention is: **never remove or rename the join-key fields without coordinating a meta-governance update in `ai2ai-gate`**. Adding new fields is fine; renaming or removing the keys above breaks every consistency table downstream.

---

## 7. Principle 6 — scope discipline

Every ship-gate artifact already carries:

- `version` (e.g. `v0.6.3`)
- `ai_memory_git_ref` (e.g. `release/v0.6.3`)
- `ai_memory_commit` (e.g. `2cfcc18`)
- `campaign_run_id` (e.g. `25007261531`)
- Phase-level `notes` (e.g. "kill_primary_mid_write convergence_bound = 1.0")

Per-droplet identity is implicit: ship-gate's three peers are `node-a`, `node-b`, `node-c`, named in the Terraform module and surfaced in per-phase reports under `runs/<campaign-id>/phase*.json`. The `chaos-client` droplet is the orchestrator and does not carry workload state.

This document codifies that **artifacts must not be cross-pollinated across campaigns or releases**:

- A ship-gate run for `v0.6.3` produces evidence about `v0.6.3` only. Rolling its verdict forward to `v0.6.3.1` without re-running the campaign is not allowed.
- A per-release A2A campaign joining ship-gate findings to NHI correlates must use the join key for *its own* release; using a different release's ship-gate evidence to fill a gap invalidates the consistency table.
- The fault model under test (the chaos class set in Phase 4) is part of the artifact's scope. Reading "convergence_bound = 1.0 under `kill_primary_mid_write`" as if it covered `network_partition` is a scope violation.

---

## 8. Forward-looking: expected-RED canaries

### The gap

Per-release A2A campaigns embed **expected-RED canaries** (S23, S24) in their substrate cert. These are scenarios with a known-open bug whose expected outcome on the current release is RED. They serve a single, distinct purpose: **they prove the harness can detect a real defect**. If a known-RED canary unexpectedly turns GREEN, the harness is broken — not the product — and the campaign is halted under the canonical doc's Principle 2.

ship-gate currently has no analog. Every ship-gate phase is expected to be GREEN on a release-candidate ref; a RED phase is interpreted as a real product defect, and the release is blocked. This is operationally correct but leaves an integrity gap: there is no ongoing proof that the ship-gate harness *can* detect a defect. A silent harness regression — a phase script that always returns `pass: true` regardless of actual state — would not be caught until a real defect slipped past it into production.

### The commitment

This document commits ship-gate to add at least one expected-RED canary as a harness-integrity self-test. Candidate forms (the actual choice is deferred to the implementation PR):

- **Phase 1 canary (assertion-detection):** a per-node assertion deliberately wired to fail (e.g. "expect `tools/list` to return ≥ 9999 tools"). The phase script emits `pass: false` for this single assertion. The aggregator must classify this case as "harness canary RED" and **not** flip `overall_pass` to false on its account, while still ensuring that if the canary unexpectedly passes the campaign is halted.
- **Phase 2 canary (federation classification):** a deliberately misclassified probe — submit a write under conditions where the expected response is precisely *opposite* the probe's normal classification. If the harness classifies it the "passing" way, the harness is wrong.
- **Phase 4 canary (chaos-floor):** a chaos class with a known floor below `0.995` (e.g. a fault model that ai-memory-mcp explicitly does not claim to handle). The harness must report this class red and continue.

Whichever form is chosen, the canary must satisfy three properties:

1. **Always-RED on a fixed ai-memory ref** until a planned fix lands. The fix landing flips the canary; the harness must then halt and require an updated baseline.
2. **Distinct in artifacts.** The canary's RED status must not pollute `overall_pass`. The release-summary schema may need a `canaries` sub-object alongside `phases`; that's an implementation question for the canary PR.
3. **Documented in `docs/methodology.md`.** Operators reading the methodology must know which RED-looking output is a canary and which is a real failure.

### Tracking

This commitment is tracked as a forward-looking item, **not implemented in this PR**. The canary PR is a separate change that will:

1. Add the canary to one or more of `scripts/phase{1,2,4}_*.sh`.
2. Update `releases/schema.json` to surface canary state.
3. Update `docs/methodology.md` to explain the canary semantics.
4. Update `scripts/collect_reports.sh` to classify canary state correctly in `overall_pass`.

Tracking issue: TBD on filing of this PR; will be linked from `releases/schema.json` once filed.

Until that PR lands, ship-gate's harness-integrity claim rests on:

- Reproducibility — a third party can re-run the campaign on their own DigitalOcean account.
- Public artifacts — every assertion is paired with a JSON file under `runs/`.
- Schema enforcement — `release-summary-gate.yml` rejects malformed summaries.

These are necessary but not sufficient. The expected-RED canary is the missing piece.

---

## 9. Out of scope for this document

Listed for absolute clarity, so a reader does not infer this document changes things it does not change.

- **Phase mechanics.** [`docs/methodology.md`](methodology.md) and [`docs/phases/`](phases/) remain authoritative on what each phase measures and how. This document does not modify them.
- **Scripts, terraform, workflows.** No script under `scripts/`, no module under `terraform/`, no workflow under `.github/workflows/` is changed by this document.
- **Existing release artifacts.** `releases/v0.6.3/summary.json` and any prior `releases/<version>/summary.json` remain valid under the existing schema. The new `nhi_verdict` field is optional with a `null` default, so existing artifacts continue to validate.
- **The 14-day soak.** [`docs/soak.md`](soak.md) is its own surface and is not governed by this document.
- **Canary implementation.** Per §8, the canary is a forward-looking commitment, not implemented here.
- **Per-release A2A campaign internals.** The per-release campaigns are governed by their own `docs/governance.md`, which inherits from the canonical `ai2ai-gate/docs/governance/META-GOVERNANCE.md`. ship-gate does not govern them; it only provides the substrate evidence and the join keys they consume.

---

## 10. Change control

Edits to this document follow the meta-governance discipline:

1. **Cosmetic edits** (typos, link fixes, table formatting) — direct PR, single reviewer.
2. **Substantive edits** that change which principles ship-gate claims to instantiate, how the join keys work, or what `nhi_verdict` means — require a sibling PR to `ai2ai-gate/docs/governance/META-GOVERNANCE.md` so the canonical doc and this instantiation stay coherent.
3. **Adding/removing a principle from the "applies to ship-gate" list** — requires sibling PRs to all three repos in the topology and explicit sign-off from the release-train operator.

The `nhi_verdict: null` contract in particular is **load-bearing** for downstream consumers. Changing its semantics is a category-3 edit.

---

## 11. References

- Canonical First-Principles document (in flight): `<placeholder: ai2ai-gate#TBD>` — `ai-memory-ai2ai-gate/docs/governance/META-GOVERNANCE.md`.
- Per-release A2A v0.6.3.1 instantiation: [`ai-memory-a2a-v0.6.3.1/docs/governance.md`](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/blob/refactor/first-principles-governance/docs/governance.md), authored in [PR #2](https://github.com/alphaonedev/ai-memory-a2a-v0.6.3.1/pull/2).
- ship-gate methodology: [`docs/methodology.md`](methodology.md).
- ship-gate phase pages: [`docs/phases/phase1.md`](phases/phase1.md), [`phase2.md`](phases/phase2.md), [`phase3.md`](phases/phase3.md), [`phase4.md`](phases/phase4.md).
- Release surface schema: [`releases/schema.json`](../releases/schema.json).

---

*End of document.*
