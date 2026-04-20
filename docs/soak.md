# 14-day soak testing

The ship-gate campaign (`campaign.yml`) is the point-in-time release
gate. The **soak campaign** (`soak.yml`) is the long-horizon
complement: is the same release still green 24, 48, 168, 336 hours
after it was certified? A ship-gate-green release that regresses
under repeated back-to-back dispatches would indicate a subtle state
drift, environment drift, or supply-chain issue that a single run
can't catch.

v0.6.0 is the first release to run under the 14-day soak. This page
is the methodology.

---

## Assertions the soak defends

Every soak campaign exercises the same four phases the release gate
does. The soak-level invariants layer on top:

1. **No PASS-to-FAIL regression under repeated dispatch.** Once a
   ship-gate campaign returns `overall_pass: true` for a release,
   every subsequent soak dispatch against that same release SHA must
   also return `overall_pass: true`. A single red run within the
   soak window is a soak failure.
2. **Convergence bound stability on kill_primary_mid_write.** The
   Phase 4 `convergence_bound` for `kill_primary_mid_write` must
   remain at 1.0 across every soak run. A drop below 0.995 is a
   soak failure even if the phase's `pass` flag stays true.
3. **Wall-clock drift.** Total campaign duration should stay within
   a ±25% band of the ship-gate baseline (~13-15 min for v0.6.0).
   A slow creep upward points at performance regression in a
   dependency (DO provisioning, rustls version, axum version).
4. **Package-manager liveness.** Every soak run is a fresh DO
   droplet that `apt install`s / `brew`-equivalents the SAME
   v0.6.0 artifacts that shipped to customers. A failure to fetch
   the published artifact surfaces a supply-chain regression
   (Homebrew tap broken, Ubuntu PPA gone, GHCR image deleted).
5. **Cost envelope.** Each soak run is expected at ~$0.10 of
   DigitalOcean compute. Cumulative 14-day spend with 4-hour
   cadence = 84 runs × $0.10 = ~$8.40. A sudden increase in
   per-run cost is itself a soak failure (indicates misconfiguration,
   hung teardown, or larger droplets).

---

## Schedule

- **Cadence**: every 4 hours on cron. 6 runs/day × 14 days = **84
  soak runs** per release.
- **Kick-off**: triggered manually at release tag + 1 hour (so the
  release pipeline settles first). v0.6.0 soak kicked off
  2026-04-20 at ~19:30 UTC.
- **Termination**: after 14 days, the scheduled workflow disables
  itself. Operator re-enables for the next release or extends the
  window.
- **Job name convention**: `soak-v0.6.0-rN` where N is the
  ordinal within the soak window (1 through 84). Artefacts commit
  to `runs/soak-v0.6.0-rN/` alongside the original ship-gate runs,
  so the unified dashboard sees both.

---

## Pass criterion for the 14-day window

The soak is GREEN if:

- Every one of the 84 runs returns `overall_pass: true`, AND
- Every Phase 4 `kill_primary_mid_write` convergence_bound is ≥ 0.995, AND
- The p99 campaign duration is ≤ 20 minutes (20% above the
  baseline median of ~14 min allows for DO provisioning variance).

Any other outcome is a soak failure. A soak failure does NOT
automatically yank the release — it opens an investigation. The
release stays shipped unless the investigation concludes that real
customer data-path risk exists, in which case a yank + v0.6.0.1
follows.

---

## Dashboard

The runs table at [`/runs/`](runs/) aggregates every soak-prefixed
campaign alongside the release campaigns. Each soak run has the
same per-phase PASS/FAIL columns. A histogram of `campaign_duration_s`
across the 84 runs is auto-generated in [`/soak-stats/`](soak-stats/)
after every dispatch (TODO: first version will ship in the soak's
second week once enough samples exist).

For the v0.6.0 soak specifically:

- [Soak-filtered runs table](runs/#v060-soak) — direct link to the
  soak subset once at least one soak run has completed.
- Per-soak-run evidence HTML: `/evidence/soak-v0.6.0-rN/` (same
  format as the ship-gate evidence pages).

---

## Out of scope

- **Real-user workload.** This is synthetic. The test memories
  written during each soak run are the ship-gate's own corpus;
  no customer data touches the droplets. The soak is evidence
  about infrastructure + build correctness, not about production
  use patterns.
- **LLM-mediated soak.** Ollama isn't on the soak droplets (same
  reason it isn't on the ship-gate droplets — bumping to
  `s-4vcpu-16gb` for Gemma 4 E2B would triple per-run spend).
  LLM soak is a separate campaign shape tracked in the
  ai-memory-mcp `RUNBOOK-curator-soak.md`.
- **Chaos soak.** The chaos Phase 4 in the soak runs the default
  single fault class (kill_primary_mid_write). A separate soak
  variant with all four fault classes may land as v0.6.0.1+
  once partition_minority is closed.

---

## Related

- [Methodology](methodology.md) — the ship-gate protocol that
  every soak run exercises.
- [Reproducing](reproducing.md) — you can reproduce any soak run
  on your own DigitalOcean account.
- [Security](security.md) — same posture as the ship-gate.
