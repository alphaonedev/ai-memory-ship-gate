# Contributing

This repo tests [ai-memory-mcp](https://github.com/alphaonedev/ai-memory-mcp).
Bugs in the _test infrastructure itself_ (Terraform, scripts,
workflows, docs) get filed and fixed here. Bugs in ai-memory-mcp's
behavior get filed in its own repo with a link to the failing
campaign.

## Before opening a PR

1. Run `bash -n scripts/*.sh` — pure-syntax check on all phase
   scripts.
2. If you changed `terraform/*.tf`: `terraform fmt -check -recursive`
   + `terraform validate`.
3. If you changed `docs/`: `mkdocs build --strict` (requires
   `pip install mkdocs-material`).
4. If you changed the workflow: test by dispatching the workflow
   against a non-release branch and verifying teardown happens
   even on forced failure.

## New fault classes (Phase 4)

To add a fault class:

1. Add the injection function in
   `ai-memory-mcp/packaging/chaos/run-chaos.sh`.
2. Add it to the loop in `scripts/phase4_chaos.sh`.
3. Add a row to `docs/phases/phase4.md` describing what it
   exercises.
4. Include a rationale — what fault mode does this catch that the
   existing four don't?

## Cost-optimization ideas welcome

Cheaper campaigns without losing validation signal are always
accepted. Current baseline is ~$0.65 per clean run; PRs that
demonstrably lower that (while keeping every existing assertion
green) are straight merges.

## Security

Never paste tokens in issues, PRs, or commit messages.
`security@alphaone.dev` for vulnerability disclosure.

## Code style

- Shell: Bash, `set -euo pipefail` at the top, quoted
  `"$variables"`, functions for multi-step logic.
- Terraform: `terraform fmt` mandatory.
- Markdown: wrap at ~72 chars, use fenced code blocks with
  explicit language.
