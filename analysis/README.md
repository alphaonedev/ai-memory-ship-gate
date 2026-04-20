# Per-run AI NHI analysis

Every campaign run must leave a narrative trail — not just JSON —
so reviewers across three audiences (non-technical users, C-level
decision makers, engineers/architects) can understand what the run
proved. This directory is where that trail lives.

## The data contract

`run-insights.json` is a map keyed by `campaign-id`. Every entry
has the same schema:

```json
{
  "v0.6.0.0-final-rN": {
    "headline": "One-sentence verdict",
    "verdict": "One short paragraph: what the run demonstrated.",
    "what_it_tested": "Scope of this specific campaign.",
    "what_it_proved": "Proved or disproved what, concretely.",
    "for_non_technical": "Plain-language framing for a non-technical reader.",
    "for_c_level": "Risk, cost, audit, velocity framing.",
    "for_sme": "Technical depth: file paths, commits, invariants.",
    "bugs": [
      {
        "title": "What broke",
        "impact": "Consequence in the field (or in test)",
        "root_cause": "One-line technical explanation",
        "fixed_in": [
          {"label": "PR #NNN (MERGED)", "url": "https://..."}
        ]
      }
    ],
    "next_run_change": "What lands between this run and the next."
  }
}
```

`scripts/generate_run_html.sh` reads this file and renders each
field into the per-run `index.html` — the tri-audience block, the
bugs-with-fix-links list, and the next-run delta. If a run has no
entry the generator emits a placeholder noting that analysis is
pending, and raw evidence below is unaffected.

## The per-run workflow

Every ship-gate campaign **must** be followed by one of these
updates before the next run is dispatched.

1. **Read the new run's artefacts.** Open
   `runs/<campaign-id>/index.html` in a browser. Read each phase's
   Test Results checklist; confirm which asserts passed, which
   failed, and why.
2. **Append a block** to `analysis/run-insights.json`. Copy the
   schema above, fill in every field. Do not skip audiences — each
   one earns its own sentence.
3. **Link every bug to its fix.** If the run surfaced a bug, file
   an issue or open a PR first, then pin the URL in `bugs[].fixed_in`.
   If a bug is discovered during the run but not yet fixed, still
   record it with an empty `fixed_in` — a follow-up PR can backfill.
4. **Regenerate HTML.** Run
   `./scripts/generate_run_html.sh runs/<campaign-id>` locally to
   verify the narrative renders. The production build path (and
   the campaign workflow) will regenerate at deploy time anyway.
5. **Commit + push.** Push to `main`. The Pages workflow rebuilds
   the site and mirrors the updated HTML to
   `https://alphaonedev.github.io/ai-memory-ship-gate/evidence/<campaign-id>/`.

## Why the three audiences are non-negotiable

Correctness claims land differently depending on the reader. The
same JSON artefact that reads as "the cluster converged at 200/200
on all peers" to an SME reads as nothing at all to a VP of
Engineering trying to decide whether to approve a release. Three
framings on the same underlying truth is what turns evidence into
a decision-support tool.

If any of the three audience fields is missing, the insight block
is incomplete and the PR should be held. Apply the same rigor to
`what_it_tested` and `what_it_proved` — those answer the reader's
first two questions before they read anything else.
